import 'package:flutter/material.dart';

/// Minimal Material theme entry. Not a brand system.
class FileHopTheme {
  const FileHopTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4D3E)),
      visualDensity: VisualDensity.standard,
    );
  }
}
