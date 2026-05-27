# Toggle Sleep

A macOS menu bar app with two independent sleep-prevention features — useful for keeping AI agents
or long-running tasks alive on a MacBook.

**💻 Open laptop icon** = one or both features are active  
**🖥 Closed MacBook icon** = both features off, normal sleep behaviour

> **Caution:** preventing sleep traps heat and drains the battery faster.
> Using either feature on AC power is recommended.

---

## What it does

Two independent toggles in the menu bar:

| Toggle | What it does | Requires root |
|---|---|---|
| **Disable lid-close sleep** | Runs `pmset -a disablesleep 1` — lid can close without the Mac sleeping. Useful for running agents on a closed laptop. | Yes (sudoers rule) |
| **Caffeinate (lid open)** | Runs `caffeinate -di` — prevents both display sleep and idle sleep while the lid is open. Works on battery and AC. | No |

Both toggles remember their state across restarts.

While either feature is ON, a watchdog monitors two signals and **automatically disables both** (and
sends a macOS notification) if either persists for 30 seconds:

| Signal | Default trip threshold |
|---|---|
| Thermal pressure (macOS thermal state) | ≥ Serious |
| CPU usage | ≥ 60% |

Thresholds are one-line constants at the top of `Sources/main.swift`.

---

## Requirements

- macOS 12 (Monterey) or later — Intel or Apple Silicon
- Xcode Command Line Tools: `xcode-select --install`

---

## Quick install

```bash
git clone https://github.com/fabioveneto/toggle-mac-lid-sleep.git
cd toggle-mac-lid-sleep
bash install.sh
```

`install.sh` will ask for your password **once** to create the sudoers rule, then build the app and
copy it to `/Applications`.

Launch it:

```bash
open "/Applications/Toggle Sleep.app"
```

The app has no Dock icon — look for the MacBook icon in your menu bar.

### Launch at login (optional)

**System Settings → General → Login Items** → click **+** → select Toggle Sleep.

---

## Manual install

If you prefer to run each step yourself:

### 1. Grant passwordless sudo for pmset

```bash
sudo bash scripts/install-sudoers.sh
```

Verify it worked (no password prompt = success):

```bash
sudo -n /usr/bin/pmset -a disablesleep 0 && echo "OK"
```

### 2. Build

```bash
bash build.sh
```

Produces `Toggle Sleep.app` in the project directory. To also copy it to `/Applications`:

```bash
bash build.sh --install
```

### 3. Run

```bash
open "Toggle Sleep.app"
```

---

## Uninstall

```bash
sudo bash uninstall.sh
```

This will:
1. Quit the app (if running)
2. Restore `disablesleep 0` (normal sleep)
3. Remove the sudoers rule from `/etc/sudoers.d/toggle-sleep`
4. Delete `/Applications/Toggle Sleep.app`
5. Remove app preferences

---

## Usage

Click the menu bar icon to open the menu:

```
☑ Disable lid-close sleep
☐ Caffeinate (lid open)
──────────────────────────────
Thermal: Nominal
CPU Usage: 4%
Trip at Thermal ≥ Serious or CPU ≥ 60%
──────────────────────────────
Quit
```

- **Disable lid-close sleep** — prevents sleep when the lid closes (checkmark = active)
- **Caffeinate (lid open)** — prevents display + idle sleep while the lid is open (checkmark = active)
- **Thermal / CPU Usage** — live readings, updated every 12 seconds while either feature is ON
- **Quit** — restores `disablesleep 0` and kills caffeinate before exiting

---

## Adjusting thresholds

Edit the constants at the top of `Sources/main.swift`:

```swift
let thermalTripState = ProcessInfo.ThermalState.serious  // .fair | .serious | .critical
let cpuThresholdPct  = 60.0   // 0–100 %
let pollIntervalSec  = 12.0   // seconds between CPU polls
let sustainSec       = 30.0   // how long condition must hold before tripping
```

Thermal states in order: `nominal → fair → serious → critical`. The `serious` state means macOS is
actively throttling due to heat; `critical` means the system is at risk. Start with `serious` (the
conservative default) and raise to `critical` if the safeguard trips too often during normal
workloads.

Rebuild and relaunch after any change:

```bash
bash build.sh && pkill -f "Toggle Sleep"; open "Toggle Sleep.app"
```

---

## How the sudoers rule works

The installer creates `/etc/sudoers.d/toggle-sleep` with two exact-match entries:

```
<your-username> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
<your-username> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
```

`<your-username>` is filled in automatically by `scripts/install-sudoers.sh` using `logname`.

These are exact-match rules — only those two specific invocations are passwordless. Any other
`sudo` command still requires your password. To remove the rule manually:

```bash
sudo rm /etc/sudoers.d/toggle-sleep
```

---

## Why thermal state instead of a °C reading

The `smc` temperature sampler was removed from `powermetrics` in macOS 26. Rather than relying on
private/changing APIs, Toggle Sleep uses `ProcessInfo.thermalState` — the OS's own thermal signal.
It works on all macOS versions from 12 onwards, on both Intel and Apple Silicon, and requires no
root access. The trade-off is that it reports a category (Nominal / Fair / Serious / Critical) rather
than an exact temperature, but for a safeguard that's more actionable anyway.

---

## Troubleshooting

**Menu bar icon doesn't appear**  
Your menu bar may be full. Try hiding other status items, or check if the app is actually running:
`pgrep -f "Toggle Sleep"`.

**Toggle has no effect / pmset fails silently**  
Verify the sudoers rule is in place and working:
```bash
sudo -n /usr/bin/pmset -a disablesleep 0 && echo "sudoers OK"
```
If that fails with "a password is required", re-run `sudo bash scripts/install-sudoers.sh`.

**Safeguard trips immediately**  
The default CPU threshold (60%) may be too conservative for your workload. Raise `cpuThresholdPct`
in `Sources/main.swift`, rebuild, and relaunch.

**Sleep isn't restored after quitting**  
If the app was force-quit, run: `sudo pmset -a disablesleep 0`

---

## License

[MIT](LICENSE)
