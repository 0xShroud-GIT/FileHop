import 'dart:io';

import 'package:filehop/transport/transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mission 07 FINAL callback-serialization + loss-correlation contracts
/// (D-07-16).
///
/// Evidence classes:
/// - A: the executable Dart harness below runs the serialized-queue
///   semantics (generation check AFTER dispatch) and the resolved-path
///   loss-correlation algorithm deterministically. It does NOT prove
///   native thread scheduling — that stays C.
/// - B: Kotlin source contracts lock the single-state-authority structure
///   (dispatchState helper, all callbacks dispatching, generation checks
///   inside dispatched blocks, no synchronized tokens, entry-point thread
///   checks).
/// - C: real NSD callback threading remains NOT_RUN on the device
///   checklists.
void main() {
  const String instanceX = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const String instanceY = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  LanRegistrationPathBindings fresh() {
    return LanRegistrationPathBindings(globalOwnership: LanPathOwnership());
  }

  group(
    'serialized callback gate (queued stale callbacks, D-07-16 §20/28/29)',
    () {
      test(
        'queued stale callback from generation 1 is dropped at execution',
        () {
          final gate = LanCallbackGate(generation: 1);
          var state = 'generation-1';
          gate.submit(1, () => state = 'mutated-by-gen-1');
          // Stop generation 1 and start generation 2 BEFORE the queue drains:
          // the queued block must observe the NEW generation and drop itself.
          gate.setGeneration(2);
          state = 'generation-2';
          gate.drain();
          expect(state, 'generation-2');
          expect(gate.executedCount, 0);
          expect(gate.droppedCount, 1);
        },
      );

      test('queued stale update cannot resurrect state after cleanup', () {
        // §28: R owns A→X; update B→X queued; stop/cleanup runs first;
        // queued update executes afterward → dropped, no resurrection.
        final r = fresh();
        final gate = LanCallbackGate(generation: 1);
        r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkA|FileHop',
          instanceId: instanceX,
        );
        gate.submit(1, () {
          r.bindPath(
            registrationKey: 'reg1',
            pathKey: 'networkB|FileHop',
            instanceId: instanceX,
          );
        });
        // Cleanup happens first (generation still 1, owner removed).
        expect(r.cleanupRegistration('reg1'), <String>{instanceX});
        // Generation moves on before the queued update executes.
        gate.setGeneration(2);
        gate.drain();
        expect(gate.droppedCount, 1);
        expect(r.bindingsOf('reg1'), isEmpty);
        expect(r.globalOwnership.ownersOf(instanceX), isEmpty);
      });

      test('queued stale loss cannot double-remove or corrupt maps', () {
        // §29: R owns A→X; loss A queued; stop/cleanup runs first; the
        // queued loss then executes → dropped, no duplicate candidateLost.
        final r = fresh();
        final gate = LanCallbackGate(generation: 1);
        r.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkA|FileHop',
          instanceId: instanceX,
        );
        gate.submit(1, () {
          r.unbindPath(registrationKey: 'reg1', pathKey: 'networkA|FileHop');
        });
        // Cleanup removed the binding and its final owner first.
        expect(r.cleanupRegistration('reg1'), <String>{instanceX});
        gate.setGeneration(2);
        gate.drain();
        expect(gate.droppedCount, 1);
        expect(r.bindingsOf('reg1'), isEmpty);
        expect(r.globalOwnership.ownersOf(instanceX), isEmpty);
      });

      test('interleavings produce deterministic final owner sets (§27)', () {
        // Ordering A: bind A→X, loss A, bind B→X.
        final rA = fresh();
        rA.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkA|FileHop',
          instanceId: instanceX,
        );
        rA.unbindPath(registrationKey: 'reg1', pathKey: 'networkA|FileHop');
        rA.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkB|FileHop',
          instanceId: instanceX,
        );
        expect(rA.globalOwnership.ownersOf(instanceX), <String>{
          'networkB|FileHop',
        });

        // Ordering B: bind A→X, bind B→X, loss A.
        final rB = fresh();
        rB.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkA|FileHop',
          instanceId: instanceX,
        );
        rB.bindPath(
          registrationKey: 'reg1',
          pathKey: 'networkB|FileHop',
          instanceId: instanceX,
        );
        rB.unbindPath(registrationKey: 'reg1', pathKey: 'networkA|FileHop');
        expect(rB.globalOwnership.ownersOf(instanceX), <String>{
          'networkB|FileHop',
        });
      });
    },
  );

  group('resolved-path loss correlation fallback (D-07-16 §22–26)', () {
    test('concrete path loss finds the registration even when the seed-key '
        'lookup misses', () {
      // registrationKey = -|FileHop, pathOwners = {NetworkA|FileHop → X}.
      final r = fresh();
      r.bindPath(
        registrationKey: '-|FileHop',
        pathKey: '-|FileHop',
        instanceId: instanceX,
      );
      r.refineSeedBinding(
        registrationKey: '-|FileHop',
        instanceId: instanceX,
        resolvedKey: 'networkA|FileHop',
      );
      // Direct lookup by the concrete path key would miss (registration
      // still indexed under its seed). Ownership-based correlation must
      // find it and remove only that binding.
      final result = r.correlateResolvedPathLoss(
        registrationKeysOfCurrentGeneration: <String>['-|FileHop'],
        pathKey: 'networkA|FileHop',
      );
      expect(result.removed, isTrue);
      expect(result.ambiguous, isFalse);
      expect(result.finalLoss, isTrue); // X had only this owner.
      expect(r.bindingsOf('-|FileHop'), isEmpty);
      expect(r.globalOwnership.ownersOf(instanceX), isEmpty);
    });

    test('partial concrete-path loss keeps the candidate', () {
      // R: A→X, B→X; loss A → B survives, NO candidateLost(X).
      final r = fresh();
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
      final result = r.correlateResolvedPathLoss(
        registrationKeysOfCurrentGeneration: <String>['reg1'],
        pathKey: 'networkA|FileHop',
      );
      expect(result.removed, isTrue);
      expect(result.finalLoss, isFalse);
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkB|FileHop',
      });
    });

    test('different-instance loss isolation', () {
      // R: A→X, B→Y; loss A → X loses (final), Y/B untouched.
      final r = fresh();
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
      final result = r.correlateResolvedPathLoss(
        registrationKeysOfCurrentGeneration: <String>['reg1'],
        pathKey: 'networkA|FileHop',
      );
      expect(result.removed, isTrue);
      expect(result.finalLoss, isTrue); // X had only A.
      expect(r.globalOwnership.ownersOf(instanceX), isEmpty);
      expect(r.globalOwnership.ownersOf(instanceY), <String>{
        'networkB|FileHop',
      });
    });

    test('unknown concrete path loss is ignored', () {
      final r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      final result = r.correlateResolvedPathLoss(
        registrationKeysOfCurrentGeneration: <String>['reg1'],
        pathKey: 'networkZ|FileHop',
      );
      expect(result.removed, isFalse);
      expect(result.ambiguous, isFalse);
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkA|FileHop',
      });
    });

    test('ambiguous concrete path loss removes none (defensive)', () {
      // Legitimate trigger for the defensive branch: the same concrete
      // path key bound under two DIFFERENT instances by two registrations
      // (two advertisers sharing network+name with different TXT instance
      // IDs — the documented D-07-12 physical C limitation). A path loss
      // that matches two registrations must fail conservatively.
      final r = fresh();
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      r.bindPath(
        registrationKey: 'reg2',
        pathKey: 'networkA|FileHop',
        instanceId: instanceY,
      );
      final result = r.correlateResolvedPathLoss(
        registrationKeysOfCurrentGeneration: <String>['reg1', 'reg2'],
        pathKey: 'networkA|FileHop',
      );
      expect(result.removed, isFalse);
      expect(result.ambiguous, isTrue);
      // Nothing removed: both bindings survive untouched.
      expect(r.bindingsOf('reg1'), <String, String>{
        'networkA|FileHop': instanceX,
      });
      expect(r.bindingsOf('reg2'), <String, String>{
        'networkA|FileHop': instanceY,
      });
      expect(r.globalOwnership.ownersOf(instanceX), <String>{
        'networkA|FileHop',
      });
      expect(r.globalOwnership.ownersOf(instanceY), <String>{
        'networkA|FileHop',
      });
    });

    test('removeBinding removes only the identified path', () {
      final r = fresh();
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
      final result = r.removeBinding(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
      );
      expect(result.removed, isTrue);
      expect(result.finalLoss, isTrue); // X lost its final owner.
      expect(r.globalOwnership.ownersOf(instanceY), <String>{
        'networkB|FileHop',
      });
    });
  });

  group('pathless loss semantics preserved (D-07-16 §18)', () {
    test('0 / 1 / many pathless loss outcomes', () {
      final r = fresh();
      expect(r.pathlessLoss('reg1').outcome, LanPathlessLossOutcome.stale);
      r.bindPath(
        registrationKey: 'reg1',
        pathKey: 'networkA|FileHop',
        instanceId: instanceX,
      );
      final one = r.pathlessLoss('reg1');
      expect(one.outcome, LanPathlessLossOutcome.removedOne);
      expect(one.finalLoss, isTrue);
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
      final many = r.pathlessLoss('reg1');
      expect(many.outcome, LanPathlessLossOutcome.ambiguous);
      expect(r.globalOwnership.ownersOf(instanceX).length, 2);
    });
  });

  group('Kotlin single-state-authority source contracts (B)', () {
    late String discovery;
    late String plugin;

    setUpAll(() {
      discovery = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
      plugin = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopNativePlugin.kt',
      ).readAsStringSync();
    });

    test('dispatchState helper exists with the main-looper fast path', () {
      final RegExp helper = RegExp(
        r'private fun dispatchState\(block: \(\) -> Unit\) \{[\s\S]{0,300}?'
        r'Looper\.myLooper\(\) == main\.looper[\s\S]{0,200}?'
        r'main\.post\(block\)',
      );
      expect(helper.hasMatch(discovery), isTrue);
    });

    test('DiscoveryListener callbacks all dispatch before mutation', () {
      final RegExp started = RegExp(
        r'onDiscoveryStarted\(regType: String\) \{\s*(?://[^\n]*\n\s*)*'
        r'dispatchState \{',
      );
      expect(started.hasMatch(discovery), isTrue);
      final RegExp startFail = RegExp(
        r'onStartDiscoveryFailed\(regType: String, errorCode: Int\) \{\s*(?://[^\n]*\n\s*)*'
        r'dispatchState \{',
      );
      expect(startFail.hasMatch(discovery), isTrue);
      final RegExp stopped = RegExp(
        r'onDiscoveryStopped\(serviceType: String\) \{\s*(?://[^\n]*\n\s*)*'
        r'dispatchState \{',
      );
      expect(stopped.hasMatch(discovery), isTrue);
      final RegExp stopFail = RegExp(
        r'onStopDiscoveryFailed\(serviceType: String, errorCode: Int\) \{\s*(?://[^\n]*\n\s*)*'
        r'dispatchState \{',
      );
      expect(stopFail.hasMatch(discovery), isTrue);
      final RegExp found = RegExp(
        r'onServiceFound\(service: NsdServiceInfo\) \{\s*(?://[^\n]*\n\s*)*'
        r'dispatchState \{ handleFound\(service, gen\) \}',
      );
      expect(found.hasMatch(discovery), isTrue);
      final RegExp lost = RegExp(
        r'onServiceLost\(service: NsdServiceInfo\) \{\s*(?://[^\n]*\n\s*)*'
        r'dispatchState \{ handleLost\(service, gen\) \}',
      );
      expect(lost.hasMatch(discovery), isTrue);
    });

    test('legacy ResolveListener callbacks dispatch before mutation', () {
      final RegExp resolved = RegExp(
        r'onServiceResolved\(serviceInfo: NsdServiceInfo\) \{\s*(?://[^\n]*\n\s*)*'
        r'dispatchState \{ publishResolved\(serviceInfo, entry, gen\) \}',
      );
      expect(resolved.hasMatch(discovery), isTrue);
      final RegExp failed = RegExp(
        r'onResolveFailed\(serviceInfo: NsdServiceInfo, errorCode: Int\) \{'
        r'[\s\S]{0,300}?dispatchState \{ \}',
      );
      expect(failed.hasMatch(discovery), isTrue);
    });

    test('ServiceInfoCallback mutations are serialized', () {
      final RegExp updated = RegExp(
        r'onServiceUpdated\(info: NsdServiceInfo\) \{\s*(?://[^\n]*\n\s*)*'
        r'dispatchState \{ publishResolved\(info, entry, gen\) \}',
      );
      expect(updated.hasMatch(discovery), isTrue);
      final RegExp lost = RegExp(
        r'onServiceLost\(\) \{\s*(?://[^\n]*\n\s*)*'
        r'dispatchState \{ handlePathlessLoss\(entry, gen\) \}',
      );
      expect(lost.hasMatch(discovery), isTrue);
    });

    test('generation checks happen AFTER dispatch inside handlers', () {
      // handleFound/handleLost/handlePathlessLoss/publishResolved re-check
      // live(gen) at their top, i.e. after the dispatched block executes.
      final RegExp foundCheck = RegExp(
        r'private fun handleFound\(service: NsdServiceInfo, gen: Int\) \{'
        r'\s*if \(!live\(gen\)\) return',
      );
      expect(foundCheck.hasMatch(discovery), isTrue);
      final RegExp lostCheck = RegExp(
        r'private fun handleLost\(service: NsdServiceInfo, gen: Int\) \{'
        r'\s*if \(!live\(gen\)\) return',
      );
      expect(lostCheck.hasMatch(discovery), isTrue);
      final RegExp pathlessCheck = RegExp(
        r'private fun handlePathlessLoss\(entry: Tracked, gen: Int\): PathlessLossOutcome \{'
        r'\s*if \(!live\(gen\)\) return PathlessLossOutcome\.STALE',
      );
      expect(pathlessCheck.hasMatch(discovery), isTrue);
      final RegExp publishCheck = RegExp(
        r'private fun publishResolved\([\s\S]{0,300}?'
        r'if \(!live\(gen\)\) return',
      );
      expect(publishCheck.hasMatch(discovery), isTrue);
    });

    test('public entry points verify the state-thread invariant', () {
      expect(discovery.contains('fun checkStateThread()'), isTrue);
      final RegExp start = RegExp(
        r'fun startBrowse\(\): String\? \{\s*(?://[^\n]*\n\s*)*checkStateThread\(\)',
      );
      expect(start.hasMatch(discovery), isTrue);
      final RegExp stop = RegExp(
        r'fun stopBrowse\(\) \{\s*(?://[^\n]*\n\s*)*checkStateThread\(\)',
      );
      expect(stop.hasMatch(discovery), isTrue);
      expect(plugin.contains('main thread'), isTrue);
    });

    test('no synchronized locks or lock domains remain', () {
      expect(discovery.contains('@Synchronized'), isFalse);
      expect(discovery.contains('synchronized('), isFalse);
    });

    test('state collections are owned by the serialized authority', () {
      expect(
        discovery.contains(
          'private val tracked = LinkedHashMap<String, Tracked>()',
        ),
        isTrue,
      );
      expect(
        discovery.contains(
          'private val instanceToKeys = HashMap<String, MutableSet<String>>()',
        ),
        isTrue,
      );
      expect(discovery.contains('ConcurrentHashMap'), isFalse);
    });

    test('resolved-path loss fallback exists and is bounded', () {
      expect(discovery.contains('fun correlateResolvedPathLoss('), isTrue);
      final RegExp fallback = RegExp(
        r'private fun handleLost\(service: NsdServiceInfo, gen: Int\) \{'
        r'[\s\S]{0,900}?'
        r'if \(!lookupKey\.startsWith\("-|"\)\) \{[\s\S]{0,300}?'
        r'correlateResolvedPathLoss\(lookupKey, gen\)',
      );
      expect(fallback.hasMatch(discovery), isTrue);
      final RegExp bounded = RegExp(
        r'private fun correlateResolvedPathLoss\(pathKey: String, gen: Int\) \{'
        r'[\s\S]{0,700}?'
        r'it\.pathOwners\.containsKey\(pathKey\)[\s\S]{0,700}?'
        r'"concrete path loss matches multiple registrations; remove none"',
      );
      expect(bounded.hasMatch(discovery), isTrue);
      expect(discovery.contains('fun removeBinding('), isTrue);
      expect(discovery.contains('fun removeEmptyRegistration('), isTrue);
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

/// Deterministic single-queue mirror of the Android `dispatchState` rule:
/// blocks execute in submission order on one serialized queue; a block
/// whose generation differs from the CURRENT generation at execution time
/// is dropped (generation check AFTER dispatch, D-07-16). No sleeps.
class LanCallbackGate {
  LanCallbackGate({required int generation}) : currentGeneration = generation;

  int currentGeneration;
  int executedCount = 0;
  int droppedCount = 0;

  final List<void Function()> _pending = <void Function()>[];

  int get pendingCount => _pending.length;

  void submit(int generation, void Function() action) {
    _pending.add(() {
      if (generation == currentGeneration) {
        executedCount += 1;
        action();
      } else {
        droppedCount += 1;
      }
    });
  }

  void setGeneration(int generation) {
    currentGeneration = generation;
  }

  void drain() {
    while (_pending.isNotEmpty) {
      _pending.removeAt(0)();
    }
  }
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
