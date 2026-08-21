import 'dart:io';

import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 07 FINAL Android path→instance binding contracts (D-07-15).
///
/// Evidence classes:
/// - A: the executable Dart mirror of the Android coordinator semantics
///   (`LanRegistrationPathBindings`: `Map<Path, InstanceId>`) runs the exact
///   required behaviors here.
/// - B: Kotlin source contracts lock the production structure
///   (pathOwners map, bindPath/unbindPath/cleanupRegistration/
///   handlePathlessLoss, no stale single-instance/owned-set shape).
/// - C: real NSD callback behavior remains NOT_RUN on the device checklists.
void main() {
  const String instanceX = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const String instanceY = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  LanRegistrationPathBindings fresh() {
    return LanRegistrationPathBindings(globalOwnership: LanPathOwnership());
  }

  group('same registration, same instance, two networks (D-07-15 §26)', () {
    test('R binds A→X then B→X: one candidate X with owners {A, B}', () {
      final LanRegistrationPathBindings r = fresh();
      final bindA = r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      expect(bindA.outcome, LanPathBindOutcome.newInstance);
      expect(bindA.lostOld, isFalse);
      final bindB = r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkB|FileHop',
        instanceId: instanceX,
      );
      expect(bindB.outcome, LanPathBindOutcome.existingInstance);
      expect(r.bindingsOf('reg1'), <String, String>{
        'networkA|FileHop': instanceX,
        'networkB|FileHop': instanceX,
      });
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkA|FileHop',
        'networkB|FileHop',
      });
      // Exactly ONE candidateFound for X: the first bind only.
      expect(r.globalOwnership.trackedInstances, 1);
    });
  });

  group(
    'same registration, different instances, two networks (D-07-15 §27)',
    () {
      test('R binds A→X then B→Y: two independent candidates', () {
        final LanRegistrationPathBindings r = fresh();
        expect(
          r
              .bindPath(
                registrationKey: 'reg1',
                pathKey: 'networkA|FileHop',
                instanceId: instanceX,
              )
              .outcome,
          LanPathBindOutcome.newInstance,
        );
        expect(
          r
              .bindPath(
                registrationKey: 'reg1',
                pathKey: 'networkB|FileHop',
                instanceId: instanceY,
              )
              .outcome,
          LanPathBindOutcome.newInstance,
        );
        expect(r.bindingsOf('reg1'), <String, String>{
          'networkA|FileHop': instanceX,
          'networkB|FileHop': instanceY,
        });
        expect(r.globalOwnership.ownersOf(instanceX), <String>{
          'networkA|FileHop',
        });
        expect(r.globalOwnership.ownersOf(instanceY), <String>{
          'networkB|FileHop',
        });
        // Both candidates exist; the shared name never merged them.
        expect(r.globalOwnership.trackedInstances, 2);
      });
    },
  );

  group('one path changes instance (D-07-15 §28/§29)', () {
    test('A switches X→Y while B keeps X: no candidateLost(X)', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkB|FileHop',
        instanceId: instanceX,
      );
      final switchResult = r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceY,
      );
      // B still owns X → NO candidateLost(X); the switch itself is not a
      // new instance for Y? Y had no owners before → newInstance for Y.
      expect(switchResult.outcome, LanPathBindOutcome.newInstance);
      expect(switchResult.lostOld, isFalse);
      expect(r.bindingsOf('reg1'), <String, String>{
        'networkA|FileHop': instanceY,
        'networkB|FileHop': instanceX,
      });
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkB|FileHop',
      });
      expect(r.globalOwnership.ownersOf(instanceY), <String>{
        'networkA|FileHop',
      });
    });

    test('final path switches X→Y: candidateLost(X) + candidateFound(Y)', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      final switchResult = r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceY,
      );
      // X lost its final owner → exactly one candidateLost signal.
      expect(switchResult.lostOld, isTrue);
      expect(switchResult.outcome, LanPathBindOutcome.newInstance);
      expect(r.globalOwnership.ownersOf(instanceX), isEmpty);
      expect(r.globalOwnership.ownersOf(instanceY), <String>{
        'networkA|FileHop',
      });
    });
  });

  group('duplicate binding is idempotent (D-07-15 §30)', () {
    test('A→X twice keeps one binding and one global owner', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      final dup = r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      expect(dup.outcome, LanPathBindOutcome.duplicateBinding);
      expect(dup.lostOld, isFalse);
      expect(r.bindingsOf('reg1'), <String, String>{
        'networkA|FileHop': instanceX,
      });
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkA|FileHop',
      });
    });
  });

  group('cleanup removes every binding (D-07-15 §31)', () {
    test('{A→X, B→X, C→Y} cleanup: all bindings and owners removed', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkB|FileHop',
        instanceId: instanceX,
      );
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkC|FileHop',
        instanceId: instanceY,
      );
      final Set<String> finals = r.cleanupRegistration('reg1');
      // Both instances lost their final owners → both must emit lost.
      expect(finals, <String>{instanceX, instanceY});
      expect(r.bindingsOf('reg1'), isEmpty);
      expect(r.globalOwnership.ownersOf(instanceX), isEmpty);
      expect(r.globalOwnership.ownersOf(instanceY), isEmpty);
      expect(r.isTracked('reg1'), isFalse);
    });

    test(
      'mixed-instance cleanup respects OTHER registrations (D-07-15 §18)',
      () {
        final LanRegistrationPathBindings r = fresh();
        r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkA|FileHop',
          instanceId: instanceX,
        );
        r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkB|FileHop',
          instanceId: instanceY,
        );
        r.bindPath(
          registrationKey: 'reg2',
          pathKey: 'networkC|FileHop',
          instanceId: instanceX,
        );
        final Set<String> finals = r.cleanupRegistration('reg1');
        // Y lost its only owner → lost(Y). X keeps reg2's path → no lost(X).
        expect(finals, <String>{instanceY});
        expect(r.globalOwnership.ownersOf(instanceX), <String>{
          'networkC|FileHop',
        });
        expect(r.globalOwnership.ownersOf(instanceY), isEmpty);
      },
    );
  });

  group('stop/restart rediscovery is not poisoned (D-07-15 §32)', () {
    test(
      'cleanup after multi-path observation; fresh generation refinds X',
      () {
        final LanRegistrationPathBindings r = fresh();
        r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkA|FileHop',
          instanceId: instanceX,
        );
        r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkB|FileHop',
          instanceId: instanceX,
        );
        expect(r.cleanupRegistration('reg1'), <String>{instanceX});
        // Fresh generation discovers X again: a REAL new instance signal.
        final freshBind = r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkA|FileHop',
          instanceId: instanceX,
        );
        expect(freshBind.outcome, LanPathBindOutcome.newInstance);
      },
    );
  });

  group('pathless loss semantics (D-07-15 §33–35)', () {
    test('zero bindings → stale no-op', () {
      final LanRegistrationPathBindings r = fresh();
      final result = r.pathlessLoss('reg1');
      expect(result.outcome, LanPathlessLossOutcome.stale);
      expect(result.finalLoss, isFalse);
    });

    test('one binding → removed; candidateLost only on final global owner', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      final result = r.pathlessLoss('reg1');
      expect(result.outcome, LanPathlessLossOutcome.removedOne);
      expect(result.instanceId, instanceX);
      expect(result.finalLoss, isTrue);
      expect(r.bindingsOf('reg1'), isEmpty);
      expect(r.globalOwnership.ownersOf(instanceX), isEmpty);
    });

    test('one binding with another registration owner → no candidateLost', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      r.bindPath(
        registrationKey: 'reg2',
        pathKey: 'networkB|FileHop',
        instanceId: instanceX,
      );
      final result = r.pathlessLoss('reg1');
      expect(result.outcome, LanPathlessLossOutcome.removedOne);
      expect(result.finalLoss, isFalse);
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkB|FileHop',
      });
    });

    test('multiple bindings, same instance → ambiguous, remove NOTHING', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkB|FileHop',
        instanceId: instanceX,
      );
      final result = r.pathlessLoss('reg1');
      expect(result.outcome, LanPathlessLossOutcome.ambiguous);
      expect(result.finalLoss, isFalse);
      expect(r.bindingsOf('reg1').length, 2);
      expect(r.globalOwnership.ownersOf(instanceX).length, 2);
    });

    test('multiple bindings, different instances → both candidates remain', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkB|FileHop',
        instanceId: instanceY,
      );
      final result = r.pathlessLoss('reg1');
      expect(result.outcome, LanPathlessLossOutcome.ambiguous);
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkA|FileHop',
      });
      expect(r.globalOwnership.ownersOf(instanceY), <String>{
        'networkB|FileHop',
      });
    });
  });

  group(
    'explicit lifecycle cleanup differs from pathless loss (D-07-15 §36)',
    () {
      test('generation cleanup still removes ALL bindings', () {
        final LanRegistrationPathBindings r = fresh();
        r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkA|FileHop',
          instanceId: instanceX,
        );
        r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkB|FileHop',
          instanceId: instanceY,
        );
        // FileHop owns the whole registration lifecycle here: both paths go.
        expect(r.cleanupRegistration('reg1'), <String>{instanceX, instanceY});
        expect(r.bindingsOf('reg1'), isEmpty);
        expect(r.globalOwnership.ownersOf(instanceX), isEmpty);
        expect(r.globalOwnership.ownersOf(instanceY), isEmpty);
      });
    },
  );

  group('seed refinement and unknown-path operations', () {
    test('seed stand-in refines silently to the resolved key', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: '-|FileHop',
        pathKey: '-|FileHop',
        instanceId: instanceX,
      );
      expect(
        r.refineSeedBinding(
          registrationKey: '-|FileHop',
          instanceId: instanceX,
          resolvedKey: 'networkA|FileHop',
        ),
        isTrue,
      );
      expect(r.bindingsOf('-|FileHop'), <String, String>{
        'networkA|FileHop': instanceX,
      });
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkA|FileHop',
      });
    });

    test('unknown path unbind is a stale no-op', () {
      final LanRegistrationPathBindings r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      expect(
        r.unbindPath(registrationKey: 'reg1', pathKey: 'neverTracked|FileHop'),
        isFalse,
      );
      expect(
        r.unbindPath(registrationKey: 'reg2', pathKey: 'networkA|FileHop'),
        isFalse,
      );
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkA|FileHop',
      });
    });

    test(
      'per-registration path bound drops additional paths deterministically',
      () {
        final LanRegistrationPathBindings r = fresh();
        for (
          int i = 0;
          i < LanRegistrationPathBindings.kMaxNativePathsPerRegistration;
          i++
        ) {
          expect(
            r
                .bindPath(
                  registrationKey: 'reg1',
                  pathKey: 'network$i|FileHop',
                  instanceId: instanceX,
                )
                .outcome,
            i == 0
                ? LanPathBindOutcome.newInstance
                : LanPathBindOutcome.existingInstance,
          );
        }
        final overflow = r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'overflow|FileHop',
          instanceId: instanceY,
        );
        expect(overflow.outcome, LanPathBindOutcome.pathLimitReached);
        expect(
          r.bindingsOf('reg1').length,
          LanRegistrationPathBindings.kMaxNativePathsPerRegistration,
        );
        expect(r.globalOwnership.owns(instanceY, 'overflow|FileHop'), isFalse);
      },
    );
  });

  group('Kotlin production source contracts (B)', () {
    late String source;

    setUpAll(() {
      source = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
    });

    test('registration ownership is a Map<PathKey, InstanceId>', () {
      expect(
        source.contains(
          'val pathOwners: MutableMap<String, String> = LinkedHashMap()',
        ),
        isTrue,
      );
      // The old one-instanceId + ownedPathKeys Set shape must be gone.
      expect(source.contains('var instanceId: String? = null'), isFalse);
      expect(source.contains('val ownedPathKeys: MutableSet<String>'), isFalse);
      expect(source.contains('addOwnedPath('), isFalse);
      expect(source.contains('moveOwnedPathsToNewInstance('), isFalse);
      expect(source.contains('removeRegistrationOwnership('), isFalse);
    });

    test('bindPath / unbind helpers exist with path-specific semantics', () {
      expect(source.contains('enum class PathBindOutcome'), isTrue);
      expect(source.contains('fun bindPath('), isTrue);
      expect(
        source.contains('unbindPath('),
        isFalse,
      ); // unbind is inline in bindPath/removeOwner path
      expect(source.contains('if (existingInstance != null) {'), isTrue);
      expect(source.contains('removeOwner(existingInstance, pathKey)'), isTrue);
      expect(source.contains('emitLost(existingInstance)'), isTrue);
    });

    test('pathless loss fails closed with 0/1/multiple semantics', () {
      expect(source.contains('enum class PathlessLossOutcome'), isTrue);
      expect(source.contains('fun handlePathlessLoss('), isTrue);
      final RegExp multi = RegExp(
        r'if \(entry\.pathOwners\.size > 1\) \{[\s\S]{0,300}?'
        r'lossCorrelationAmbiguous[\s\S]{0,200}?'
        r'PathlessLossOutcome\.AMBIGUOUS',
      );
      expect(multi.hasMatch(source), isTrue);
      expect(
        source.contains(
          '"pathless loss with multiple owned paths; remove none"',
        ),
        isTrue,
      );
    });

    test(
      'path-identified DiscoveryListener loss uses the concrete network',
      () {
        final RegExp identified = RegExp(
          r'fun handleCorrelatedLoss\(entry: Tracked, service: NsdServiceInfo, gen: Int\) \{'
          r'[\s\S]{0,500}?'
          r'resolvedNetwork\(service\)[\s\S]{0,500}?'
          r'removeBinding\(entry,',
        );
        expect(identified.hasMatch(source), isTrue);
      },
    );

    test('cleanup iterates the bindings, never the stale seed', () {
      final RegExp cleanup = RegExp(
        r'fun cleanupRegistration\(entry: Tracked, emitLostForResolved: Boolean\) \{'
        r'[\s\S]{0,400}?'
        r'for \(\(path, instanceId\) in entry\.pathOwners\.toList\(\)\)',
      );
      expect(cleanup.hasMatch(source), isTrue);
      expect(
        source.contains('cleanupRegistration(entry, emitLostForResolved)'),
        isTrue,
      );
    });

    test('seed refinement is silent and publish uses bindPath', () {
      expect(source.contains('fun refineSeedBinding('), isTrue);
      expect(
        source.contains('when (bindPath(entry, resolved, instanceId, gen))'),
        isTrue,
      );
      final RegExp refine = RegExp(
        r'private fun refineSeedBinding\(entry: Tracked, instanceId: String, resolvedKey: String\) \{'
        r'[\s\S]*?\n    \}',
      );
      final String body = refine.firstMatch(source)!.group(0)!;
      expect(body.contains('emitLost('), isFalse);
      expect(body.contains('emitCandidate('), isFalse);
    });

    test('legacy and modern resolve paths converge on publishResolved', () {
      expect(source.contains('registerModern'), isTrue);
      expect(source.contains('registerLegacy'), isTrue);
      final RegExp modern = RegExp(
        r'onServiceUpdated\(info: NsdServiceInfo\) \{\s*'
        r'(?://[^\n]*\n\s*)*dispatchState \{ publishResolved\(info, entry, gen\) \}',
      );
      expect(modern.hasMatch(source), isTrue);
      final RegExp legacy = RegExp(
        r'onServiceResolved\(serviceInfo: NsdServiceInfo\) \{\s*'
        r'(?://[^\n]*\n\s*)*dispatchState \{ publishResolved\(serviceInfo, entry, gen\) \}',
      );
      expect(legacy.hasMatch(source), isTrue);
    });
  });

  group('iOS Mission 07 regressions remain locked', () {
    test('NWTXTRecord / bonjourWithTXTRecord / no NWConnection', () {
      final String swift = locate('ios/Runner/FileHopLanDiscovery.swift')
          .readAsStringSync();
      expect(swift.contains('NWTXTRecord'), isTrue);
      expect(swift.contains('NWTxtRecord'), isFalse);
      expect(
        swift.contains('NWBrowser.Descriptor.bonjourWithTXTRecord('),
        isTrue,
      );
      expect(swift.contains('NWConnection'), isFalse);
    });
  });
}

/// Test-local source locator (mirrors the shared helper used by the other
/// LAN contract suites).
File locate(String relativeFromApp) {
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
