# Battery Notifier

A small, event-driven Vala application that sends desktop notifications when the battery reaches 35% and each lower 5% threshold while discharging. It uses Gio D-Bus directly to communicate with UPower and your notification daemon, without polling.

Notifications have normal urgency at 35%, 30%, and 25%, and critical urgency at 20% and below. Each threshold rearms only after the battery recovers 2 percentage points above it, preventing repeated alerts from briefly reconnecting the charger. UPower restarts are handled automatically.

## Requirements

- Vala compiler (`valac`), a C compiler, and `pkg-config`.
- GLib/Gio development libraries.
- UPower and a desktop notification daemon, such as mako, running in your desktop session.

## Compile

From the project directory:

```sh
valac --pkg gio-2.0 -o battery-notifier battery-notifier.vala
```

## Run

Run as your normal user inside your desktop session:

```sh
./battery-notifier
```

Keep the process running to receive notifications. Press `Ctrl+C` to stop it.

The battery device path is currently `/org/freedesktop/UPower/devices/battery_BAT0`. If your system uses another battery device, update `BATTERY_PATH` in `battery-notifier.vala` before compiling.
