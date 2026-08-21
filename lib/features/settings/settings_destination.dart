import 'package:flutter/material.dart';

import '../../shared/identity_placeholder.dart';

class SettingsDestination extends StatelessWidget {
  const SettingsDestination({
    super.key,
    this.identity = const IdentityPlaceholder(),
  });

  static const Key bodyKey = Key('destination-settings');
  static const Key deviceNameKey = Key('identity-device-name');
  static const Key securityIdentityKey = Key('identity-security');
  static const Key disclaimerKey = Key('identity-disclaimer');

  final IdentityPlaceholder identity;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        key: bodyKey,
        padding: const EdgeInsets.all(24),
        children: [
          Text('Settings', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 16),
          Text('This device', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Device name: ${identity.deviceName}', key: deviceNameKey),
          const SizedBox(height: 8),
          Text(
            'Security identity: ${identity.securityIdentity}',
            key: securityIdentityKey,
          ),
          const SizedBox(height: 8),
          Text(IdentityPlaceholder.disclaimer, key: disclaimerKey),
        ],
      ),
    );
  }
}
