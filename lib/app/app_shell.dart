import 'package:flutter/material.dart';

import '../features/activity/activity_destination.dart';
import '../features/devices/devices_destination.dart';
import '../features/home/home_destination.dart';
import '../features/settings/settings_destination.dart';
import '../shared/shell_destination.dart';

/// Four-destination V1 shell. Selected tab is the single navigation authority.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialDestination = ShellDestination.home});

  static const Key navigationBarKey = Key('filehop-navigation-bar');

  final ShellDestination initialDestination;

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late ShellDestination _destination = widget.initialDestination;

  ShellDestination get destination => _destination;

  void select(ShellDestination next) {
    if (next == _destination) {
      return;
    }
    setState(() => _destination = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _destination.index,
        children: const [
          HomeDestination(),
          ActivityDestination(),
          DevicesDestination(),
          SettingsDestination(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        key: AppShell.navigationBarKey,
        selectedIndex: _destination.index,
        onDestinationSelected: (int index) {
          select(ShellDestination.values[index]);
        },
        destinations: [
          for (final ShellDestination item in ShellDestination.values)
            NavigationDestination(
              key: Key('nav-${item.name}'),
              icon: Icon(item.icon, semanticLabel: item.semanticLabel),
              selectedIcon: Icon(
                item.selectedIcon,
                semanticLabel: '${item.label} destination, selected',
              ),
              label: item.label,
              tooltip: item.semanticLabel,
            ),
        ],
      ),
    );
  }
}
