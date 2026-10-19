// Build: valac --pkg gio-2.0 -o battery-notifier battery-notifier.vala
// Run: ./battery-notifier (inside a desktop session with UPower and notifications).
// Watches BAT0; alerts at <=30%, then each lower 5% threshold while discharging.
// Starting below 30% alerts immediately; repeated updates do not repeat alerts.
// Each threshold rearms only after recovery 2 percentage points above it.
// Urgency is normal above 20%, critical at <=20%; UPower restarts preserve alerts.

using GLib;

public class BatteryNotifier : Object {
  private const string UPOWER = "org.freedesktop.UPower";
  private const int HYSTERESIS = 2;
  private const string BATTERY_PATH =
    "/org/freedesktop/UPower/devices/battery_BAT0";

  private DBusProxy battery;
  private DBusProxy notifications;
  private int next_threshold = 30;

  public async BatteryNotifier () throws Error {
    battery = yield new DBusProxy.for_bus (
                                           BusType.SYSTEM,
                                           DBusProxyFlags.GET_INVALIDATED_PROPERTIES,
                                           null,
                                           UPOWER,
                                           BATTERY_PATH,
                                           "org.freedesktop.UPower.Device",
                                           null
    );

    notifications = yield new DBusProxy.for_bus (
                                                 BusType.SESSION,
                                                 DBusProxyFlags.NONE,
                                                 null,
                                                 "org.freedesktop.Notifications",
                                                 "/org/freedesktop/Notifications",
                                                 "org.freedesktop.Notifications",
                                                 null
    );

    battery.g_properties_changed.connect ((changed, invalidated) => {
      check_battery ();
    });
    // Gio reloads cached properties when this well-known name gains an owner.
    battery.notify["g-name-owner"].connect (() => {
      check_battery ();
    });

    stdout.printf ("Listening for battery changes...\n");
    check_battery ();
  }

  internal void run () {
    new MainLoop ().run ();
  }

  private void check_battery () {
    if (battery.g_name_owner == null) {
      return;
    }

    var percentage = battery.get_cached_property ("Percentage");
    var state = battery.get_cached_property ("State");
    if (percentage == null || state == null) {
      return;
    }

    double level = percentage.get_double ();
    uint status = state.get_uint32 ();
    stdout.printf ("Battery: %.1f%% | State: %u\n", level, status);
    stdout.flush ();

    // Rearm recovered thresholds, never merely because a charger was connected.
    while (next_threshold < 30 && level >= next_threshold + 5 + HYSTERESIS) {
      next_threshold += 5;
    }

    // UPower state 2 means discharging.
    if (status != 2) {
      return;
    }
    if (next_threshold < 0 || level > next_threshold) {
      return;
    }

    // Skip missed thresholds without sending a burst of stale notifications.
    do {
      next_threshold -= 5;
    } while (next_threshold >= 0 && level <= next_threshold);

    var actions = new VariantBuilder (new VariantType ("as"));
    var hints = new VariantBuilder (new VariantType ("a{sv}"));
    hints.add ("{sv}", "urgency", new Variant.byte ((uint8) (level <= 20 ? 2 : 1)));
    notifications.call.begin (
                              "Notify",
                              new Variant (
                                           "(susssasa{sv}i)",
                                           "Battery Notifier", 0u, "battery-low", "Low battery",
                                           "Battery is at %.1f%%. Please connect the charger.".printf (level),
                                           actions, hints, -1
                              ),
                              DBusCallFlags.NONE,
                              -1,
                              null,
                              (obj, result) => {
      try {
        notifications.call.end (result);
      } catch (Error e) {
        stderr.printf ("Notification failed: %s\n", e.message);
      }
    });
  }
}

async int main (string[] args) {
  try {
    var notifier = yield new BatteryNotifier ();
    notifier.run ();
  } catch (Error e) {
    stderr.printf ("Error: %s\n", e.message);
    return 1;
  }

  return 0;
}
