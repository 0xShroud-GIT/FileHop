import 'package:flutter/material.dart';

class HomeDestination extends StatelessWidget {
  const HomeDestination({super.key});

  static const Key bodyKey = Key('destination-home');

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        key: bodyKey,
        padding: const EdgeInsets.all(24),
        children: [
          Text('FileHop', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 8),
          Text(
            'Share files directly with nearby people. '
            'No account and no Internet required when later missions land.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Text('Nearby', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Nearby devices will appear here in a later mission. '
            'Discovery is not running.',
          ),
          const SizedBox(height: 24),
          Text('Share actions', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Send, Receive, and Screen Share are actions, not tabs. '
            'They are not available in this shell.',
          ),
        ],
      ),
    );
  }
}
