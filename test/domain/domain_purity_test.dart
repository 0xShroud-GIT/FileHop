import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('domain layer stays pure Dart', () {
    final Directory root = Directory('lib/domain');
    expect(root.existsSync(), isTrue);
    final List<File> files = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    final RegExp forbidden = RegExp(
      r'''package:flutter/|package:filehop/native_bridge|package:crypto|dart:io|dart:ffi|sqflite|MethodChannel|EventChannel''',
    );
    for (final File file in files) {
      final String source = file.readAsStringSync();
      expect(forbidden.hasMatch(source), isFalse, reason: file.path);
    }
  });
}
