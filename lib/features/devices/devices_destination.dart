import 'package:flutter/material.dart';

class DevicesDestination extends StatelessWidget {
  const DevicesDestination({super.key});

  static const Key bodyKey = Key('destination-devices');

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        key: bodyKey,
        padding: const EdgeInsets.all(24),
        children: [
          Text('Devices', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
            'No trusted or known devices yet. Device trust arrives in a '
            'later mission. Matching names do not prove identity.',
          ),
        ],
      ),
    );
  }
}
