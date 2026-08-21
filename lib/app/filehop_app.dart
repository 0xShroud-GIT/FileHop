import 'package:flutter/material.dart';

import 'app_shell.dart';
import 'theme/filehop_theme.dart';

/// FileHop application root. Mission 01 is a local shell only: no network,
/// no engine, no identity generation.
class FileHopApp extends StatelessWidget {
  const FileHopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FileHop',
      debugShowCheckedModeBanner: false,
      theme: FileHopTheme.light(),
      home: const AppShell(),
    );
  }
}
