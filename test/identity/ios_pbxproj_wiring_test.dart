import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FileHop identity Swift sources are in the intended Xcode targets', () {
    final File project = locateIosPath('ios/Runner.xcodeproj/project.pbxproj');
    expect(project.existsSync(), isTrue);
    final String text = project.readAsStringSync();
    final _Pbxproj pbx = _Pbxproj.parse(text);

    expect(
      locateIosPath('ios/Runner/FileHopIdentitySecretStore.swift').existsSync(),
      isTrue,
    );
    expect(
      locateIosPath(
        'ios/RunnerTests/FileHopIdentitySecretStoreAllocationTests.swift',
      ).existsSync(),
      isTrue,
    );

    expect(
      pbx.sourcePhaseContains(
        pbx.sourcePhaseIdForTarget('Runner'),
        'FileHopIdentitySecretStore.swift',
      ),
      isTrue,
      reason: 'store must be in Runner PBXSourcesBuildPhase',
    );
    expect(
      pbx.sourcePhaseContains(
        pbx.sourcePhaseIdForTarget('RunnerTests'),
        'FileHopIdentitySecretStoreAllocationTests.swift',
      ),
      isTrue,
      reason: 'allocation XCTest must be in RunnerTests PBXSourcesBuildPhase',
    );
    expect(
      pbx.sourcePhaseContains(
        pbx.sourcePhaseIdForTarget('Runner'),
        'FileHopIdentitySecretStoreAllocationTests.swift',
      ),
      isFalse,
      reason: 'allocation XCTest must not compile into the app target',
    );
    expect(
      pbx.sourcePhaseContains(
        pbx.sourcePhaseIdForTarget('RunnerTests'),
        'FileHopIdentitySecretStore.swift',
      ),
      isFalse,
      reason: 'production store must not be duplicated into RunnerTests',
    );
  });
}

File locateIosPath(String relativeFromApp) {
  for (final String path in <String>[
    relativeFromApp,
    '../$relativeFromApp',
    'app/$relativeFromApp',
  ]) {
    final File file = File(path);
    if (file.existsSync()) {
      return file;
    }
  }
  return File(relativeFromApp);
}

class _Pbxproj {
  _Pbxproj(this._text);

  final String _text;

  factory _Pbxproj.parse(String text) => _Pbxproj(text);

  String sourcePhaseIdForTarget(String targetName) {
    final RegExp target = RegExp(
      r'([A-F0-9]{24}) /\* ' +
          RegExp.escape(targetName) +
          r' \*/ = \{\s*isa = PBXNativeTarget;.*?buildPhases = \((.*?)\);',
      dotAll: true,
    );
    final Match? match = target.firstMatch(_text);
    expect(match, isNotNull, reason: 'missing PBXNativeTarget $targetName');
    final String phases = match!.group(2)!;
    final Iterable<Match> phaseIds = RegExp(r'([A-F0-9]{24}) /\* Sources \*/')
        .allMatches(phases);
    expect(phaseIds, isNotEmpty, reason: '$targetName has no Sources phase');
    return phaseIds.first.group(1)!;
  }

  bool sourcePhaseContains(String phaseId, String fileName) {
    final RegExp phase = RegExp(
      RegExp.escape(phaseId) + r' /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;.*?files = \((.*?)\);',
      dotAll: true,
    );
    final Match? match = phase.firstMatch(_text);
    expect(match, isNotNull, reason: 'missing PBXSourcesBuildPhase $phaseId');
    return match!.group(1)!.contains(fileName);
  }
}
