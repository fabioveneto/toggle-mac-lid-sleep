import Cocoa
import Foundation

// MARK: - Editable thresholds
// Thermal state order: nominal < fair < serious < critical
let thermalTripState = ProcessInfo.ThermalState.serious  // trip when state reaches this or above
let cpuThresholdPct  = 60.0   // overall CPU busy % — lower = more protective
let pollIntervalSec  = 12.0   // seconds between CPU polls (only while toggle is ON)
let sustainSec       = 30.0   // condition must persist this long before tripping

// MARK: - Process helpers

@discardableResult
func run(_ exe: String, _ args: [String]) -> (out: String, code: Int32) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: exe)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError  = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return (String(data: data, encoding: .utf8) ?? "", p.terminationStatus)
}

func setPmset(_ on: Bool) {
    let (_, code) = run("/usr/bin/sudo",
        ["/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"])
    if code != 0 { NSLog("[ToggleSleep] pmset exit \(code)") }
}

func notify(title: String, body: String) {
    let safeBody  = body.replacingOccurrences(of: "\"", with: "'")
    let safeTitle = title.replacingOccurrences(of: "\"", with: "'")
    run("/usr/bin/osascript", ["-e",
        "display notification \"\(safeBody)\" with title \"\(safeTitle)\""])
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var watchdogTimer: Timer?
    private var hotSince: Date?
    private var lastThermal: ProcessInfo.ThermalState?
    private var lastCPU: Double?
    // CPU tick baseline; only read/written on main thread
    private var prevTicks: (u: UInt32, s: UInt32, i: UInt32, n: UInt32)?

    private var keepAwake: Bool {
        get { UserDefaults.standard.bool(forKey: "keepAwake") }
        set { UserDefaults.standard.set(newValue, forKey: "keepAwake"); applyState(newValue) }
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil)
        rebuildMenu()
        applyState(keepAwake)
    }

    func applicationWillTerminate(_: Notification) {
        if keepAwake { setPmset(false) }
    }

    // MARK: State

    private func applyState(_ on: Bool) {
        setPmset(on)
        updateIcon(on)
        if on {
            prevTicks = nil; hotSince = nil
            startWatchdog()
        } else {
            stopWatchdog()
            lastThermal = nil; lastCPU = nil
        }
        rebuildMenu()
    }

    private func updateIcon(_ on: Bool) {
        let name = on ? "laptopcomputer" : "macbook"
        if let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            img.isTemplate = true
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = on ? "●" : "○"
        }
    }

    private func rebuildMenu() {
        let m = NSMenu()

        let hdr = NSMenuItem(title: "Keep Awake: \(keepAwake ? "ON" : "OFF")",
                             action: nil, keyEquivalent: "")
        hdr.isEnabled = false
        m.addItem(hdr)

        let tog = NSMenuItem(title: "Disable lid-close sleep",
                             action: #selector(onToggle), keyEquivalent: "")
        tog.state  = keepAwake ? .on : .off
        tog.target = self
        m.addItem(tog)

        m.addItem(.separator())

        func info(_ title: String) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            i.isEnabled = false; return i
        }

        if keepAwake {
            let thermalStr = lastThermal.map { thermalName($0) } ?? "measuring…"
            let cpuStr     = lastCPU.map { String(format: "%.0f%%", $0) } ?? "measuring…"
            m.addItem(info("Thermal: \(thermalStr)"))
            m.addItem(info("CPU Usage: \(cpuStr)"))
        } else {
            m.addItem(info("Thermal: —"))
            m.addItem(info("CPU Usage: —"))
        }
        m.addItem(info("Trip at Thermal ≥ Serious or CPU ≥ \(Int(cpuThresholdPct))%"))

        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Quit",
                             action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = m
    }

    @objc private func onToggle() { keepAwake = !keepAwake }

    // MARK: Watchdog

    private func startWatchdog() {
        watchdogTimer?.invalidate()
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: pollIntervalSec,
                                             repeats: true) { [weak self] _ in self?.poll() }
    }

    private func stopWatchdog() { watchdogTimer?.invalidate(); watchdogTimer = nil; hotSince = nil }

    private func poll() {
        let thermal = ProcessInfo.processInfo.thermalState
        let cpu     = cpuUsagePct()
        onPollResult(thermal: thermal, cpu: cpu)
    }

    @objc private func thermalStateChanged() {
        // Instant reaction to OS thermal events while toggle is ON
        guard keepAwake else { return }
        poll()
    }

    private func onPollResult(thermal: ProcessInfo.ThermalState, cpu: Double?) {
        lastThermal = thermal; lastCPU = cpu
        rebuildMenu()

        let thermalHot = thermal.rawValue >= thermalTripState.rawValue
        let cpuHot     = cpu.map { $0 >= cpuThresholdPct } ?? false
        let hot        = thermalHot || cpuHot

        if hot {
            if hotSince == nil { hotSince = Date() }
            else if Date().timeIntervalSince(hotSince!) >= sustainSec { trip(thermal: thermal, cpu: cpu) }
        } else {
            hotSince = nil
        }
    }

    private func trip(thermal: ProcessInfo.ThermalState, cpu: Double?) {
        let t = thermalName(thermal)
        let c = cpu.map { String(format: "%.0f%%", $0) } ?? "n/a"
        NSLog("[ToggleSleep] safeguard tripped — thermal:%@ cpu:%@", t, c)
        keepAwake = false
        notify(title: "Toggle Sleep — Safeguard",
               body:  "Too hot (Thermal: \(t) / CPU: \(c)). Sleep re-enabled.")
    }

    // MARK: CPU usage (main thread only)

    private func cpuUsagePct() -> Double? {
        var info  = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }

        let cur = (u: info.cpu_ticks.0, s: info.cpu_ticks.1,
                   i: info.cpu_ticks.2, n: info.cpu_ticks.3)
        defer { prevTicks = cur }
        guard let prev = prevTicks else { return nil }

        let du = Int64(cur.u) - Int64(prev.u)
        let ds = Int64(cur.s) - Int64(prev.s)
        let di = Int64(cur.i) - Int64(prev.i)
        let dn = Int64(cur.n) - Int64(prev.n)
        let total = du + ds + di + dn
        guard total > 0 else { return nil }
        return Double(du + ds + dn) / Double(total) * 100.0
    }
}

// MARK: - Helpers

private func thermalName(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal:  return "Nominal"
    case .fair:     return "Fair"
    case .serious:  return "Serious ⚠️"
    case .critical: return "Critical 🔴"
    @unknown default: return "Unknown"
    }
}

// MARK: - Entry
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
