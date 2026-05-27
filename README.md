# Toggle Sleep

A macOS menu bar app that prevents your MacBook from sleeping when the lid is closed — useful for keeping AI agents or long-running tasks alive on a closed laptop.

![OFF](docs/off.png) Closed MacBook icon = sleep works normally  
![ON](docs/on.png) Open laptop icon = lid-close sleep is disabled

---

## What it does

Clicking the toggle runs `pmset -a disablesleep 1`, which tells macOS not to sleep when the lid closes. Clicking again restores normal behaviour with `pmset -a disablesleep 0`.

While the toggle is ON, a watchdog monitors two signals and **automatically re-enables sleep** (and sends a notification) if either persists for 30 seconds:

| Signal | Default trip threshold |
|---|---|
| Thermal pressure (OS-level) | ≥ Serious |
| CPU usage | ≥ 60% |

Thresholds are one-line constants at the top of `Sources/main.swift`.

---

## Requirements

- macOS 13 or later (Apple Silicon or Intel)
- Xcode Command Line Tools (`xcode-select --install`)

---

## Installation

### 1. Grant passwordless sudo for pmset

The app needs root to run `pmset`. This one-time setup creates a locked-down sudoers rule that grants passwordless access to exactly two commands and nothing else.

```bash
sudo bash scripts/install-sudoers.sh
```

Verify it worked:

```bash
sudo -n /usr/bin/pmset -a disablesleep 0 && echo "OK"
```

### 2. Build the app

```bash
bash build.sh
```

This produces `Toggle Sleep.app` in the project directory. To also copy it to `/Applications`:

```bash
bash build.sh --install
```

### 3. Run it

```bash
open "Toggle Sleep.app"
```

The app has no Dock icon. Look for the MacBook icon in the menu bar.

### 4. Launch at login (optional)

Open **System Settings → General → Login Items** and add `Toggle Sleep.app`.

---

## Usage

Click the menu bar icon to open the menu:

```
Keep Awake: OFF
☑ Disable lid-close sleep
─────────────────────
Thermal: Nominal
CPU Usage: 4%
Trip at Thermal ≥ Serious or CPU ≥ 60%
─────────────────────
Quit
```

- **Disable lid-close sleep** — toggles the feature on/off (checkmark = active)
- **Thermal / CPU Usage** — live readings, updated every 12 seconds while ON
- **Quit** — restores `disablesleep 0` before exiting

---

## Adjusting thresholds

Open `Sources/main.swift` and edit the constants at the top of the file:

```swift
let thermalTripState = ProcessInfo.ThermalState.serious  // .fair | .serious | .critical
let cpuThresholdPct  = 60.0   // 0–100 %
let pollIntervalSec  = 12.0   // seconds between CPU polls
let sustainSec       = 30.0   // how long condition must hold before tripping
```

Thermal states in order: `nominal → fair → serious → critical`. Apple Silicon throttles the CPU near `serious`; `critical` means the system is at risk. Starting at `serious` is conservative — raise to `critical` if the safeguard trips too often during normal agent workloads.

Then rebuild and relaunch:

```bash
bash build.sh && pkill -f "Toggle Sleep"; open "Toggle Sleep.app"
```

---

## How the sudoers rule works

The file installed at `/etc/sudoers.d/toggle-sleep` looks like this:

```
fabio ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0
fabio ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1
```

These are exact-match rules — only those two specific invocations are passwordless. Any other `sudo` command still requires your password. To remove it: `sudo rm /etc/sudoers.d/toggle-sleep`.
