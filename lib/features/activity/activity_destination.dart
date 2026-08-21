import 'package:flutter/material.dart';

class ActivityDestination extends StatelessWidget {
  const ActivityDestination({super.key});

  static const Key bodyKey = Key('destination-activity');

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        key: bodyKey,
        padding: const EdgeInsets.all(24),
        children: [
          Text('Activity', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 8),
          const Text(
            'No transfer activity yet. History and in-progress transfers '
            'will appear here in a later mission.',
          ),
        ],
      ),
    );
  }
}
