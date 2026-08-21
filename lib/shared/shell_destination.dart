import 'package:flutter/material.dart';

/// The four V1 bottom destinations. Send / Receive / Screen Share are not tabs.
enum ShellDestination {
  home,
  activity,
  devices,
  settings;

  String get label {
    switch (this) {
      case ShellDestination.home:
        return 'Home';
      case ShellDestination.activity:
        return 'Activity';
      case ShellDestination.devices:
        return 'Devices';
      case ShellDestination.settings:
        return 'Settings';
    }
  }

  String get semanticLabel => '$label destination';

  IconData get icon {
    switch (this) {
      case ShellDestination.home:
        return Icons.home_outlined;
      case ShellDestination.activity:
        return Icons.history_outlined;
      case ShellDestination.devices:
        return Icons.devices_outlined;
      case ShellDestination.settings:
        return Icons.settings_outlined;
    }
  }

  IconData get selectedIcon {
    switch (this) {
      case ShellDestination.home:
        return Icons.home;
      case ShellDestination.activity:
        return Icons.history;
      case ShellDestination.devices:
        return Icons.devices;
      case ShellDestination.settings:
        return Icons.settings;
    }
  }
}
