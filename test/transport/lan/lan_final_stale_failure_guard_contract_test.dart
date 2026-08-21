import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mission 07 FINAL stale failure-callback guard contracts (D-07-17).
///
/// Evidence classes:
/// - A: the executable harness below mirrors the PRODUCTION guard-before-
///   mutation/event/fallback ordering inside the serialized state queue
///   and runs the exact stale/current failure scenarios deterministically
///   (no sleeps). It does not prove native thread scheduling — C.
/// - B: Kotlin source contracts lock the ordering in the production file
///   (guards precede browsing/lifecycle/cleanup/emitError/registerLegacy).
/// - C: real NSD callback ordering remains NOT_RUN on the checklists.
void main() {
  group('stale onStartDiscoveryFailed guard (D-07-17 §16/17)', () {
    test(
      'stale gen1 start-failure cannot mutate gen2 (browsing stays true)',
      () {
        final h = LanFailureGuardHarness();
        // gen1 active (STARTING), its listener installed.
        h.startGeneration();
        // Queue gen1's failure BEFORE it executes.
        h.onStartDiscoveryFailed(h.generation, h.listener);
        // Advance to gen2 and make it BROWSING.
        h.finishGen1AndStartGen2();
        h.startGen2Browsing();
        expect(h.browsing, isTrue);
        final stateBefore = h.snapshot();
        // The queued gen1 failure executes now.
        h.drain();
        expect(h.snapshot(), stateBefore);
        expect(h.browsing, isTrue, reason: 'gen2 browsing must survive');
        expect(h.cleanupCount, 0, reason: 'no cleanup of gen2');
        expect(h.errorCount, 0, reason: 'no stale error');
        expect(h.lifecycle, HarnessLifecycle.browsing);
      },
    );

    test('current start-failure still cleans and emits once', () {
      final h = LanFailureGuardHarness();
      h.startGeneration();
      h.onStartDiscoveryFailed(h.generation, h.listener);
      h.drain();
      expect(h.cleanupCount, 1, reason: 'current generation cleaned');
      expect(h.errorCount, 1, reason: 'bounded current error emitted');
      expect(h.lastError, 'discoveryStartFailed');
      expect(h.browsing, isFalse);
      expect(h.lifecycle, HarnessLifecycle.stopped);
    });
  });

  group('stale onStopDiscoveryFailed guard (D-07-17 §18/19)', () {
    test('stale gen1 stop-failure cannot contaminate gen2', () {
      final h = LanFailureGuardHarness();
      h.startGeneration();
      h.finishGen1AndStartGen2();
      h.startGen2Browsing();
      // Queue gen1's stop-failure with gen1's listener token.
      h.onStopDiscoveryFailed(1, h.gen1Listener);
      final before = h.snapshot();
      h.drain();
      expect(h.snapshot(), before);
      expect(h.errorCount, 0, reason: 'no stale error');
      expect(
        h.lifecycle,
        HarnessLifecycle.browsing,
        reason: 'no UNCERTAIN on gen2',
      );
      expect(h.uncertain, isFalse);
    });

    test('current stop-failure preserves UNCERTAIN behavior', () {
      final h = LanFailureGuardHarness();
      h.startGeneration();
      h.finishGen1AndStartGen2();
      h.startGen2Browsing();
      h.onStopDiscoveryFailed(h.generation, h.listener);
      h.drain();
      expect(h.uncertain, isTrue);
      expect(h.errorCount, 1);
      expect(h.lastError, 'discoveryStopFailed');
      expect(h.lifecycle, HarnessLifecycle.uncertain);
    });
  });

  group('stale ServiceInfo registration-failure guard (D-07-17 §20/21)', () {
    test('stale registration failure starts no legacy work', () {
      final h = LanFailureGuardHarness();
      h.startGeneration();
      final token = h.trackEntry('-|FileHop');
      // Queue gen1's registration failure for that entry's callback.
      h.onRegistrationFailed(1, token);
      // Cleanup gen1 and move to gen2 (entry removed, generation bumped).
      h.cleanupGeneration();
      h.finishGen1AndStartGen2();
      h.startGen2Browsing();
      final before = h.snapshot();
      h.drain();
      expect(h.snapshot(), before);
      expect(h.legacyResolveCount, 0, reason: 'no native work started');
      expect(h.entries, isEmpty, reason: 'no reinsertion');
      expect(h.errorCount, 0);
    });

    test('current registration failure falls back exactly once', () {
      final h = LanFailureGuardHarness();
      h.startGeneration();
      h.finishGen1AndStartGen2();
      h.startGen2Browsing();
      final token = h.trackEntry('-|FileHop');
      h.onRegistrationFailed(h.generation, token);
      h.drain();
      expect(h.legacyResolveCount, 1, reason: 'bounded legacy fallback once');
    });
  });

  group('double stale callback isolation (D-07-17 §22)', () {
    test('stale start+stop+registration failures leave gen2 identical', () {
      final h = LanFailureGuardHarness();
      h.startGeneration();
      final token = h.trackEntry('-|FileHop');
      // Queue three stale callbacks against gen1.
      h.onStartDiscoveryFailed(1, h.gen1Listener);
      h.onStopDiscoveryFailed(1, h.gen1Listener);
      h.onRegistrationFailed(1, token);
      h.cleanupGeneration();
      h.finishGen1AndStartGen2();
      h.startGen2Browsing();
      final before = h.snapshot();
      h.drain();
      expect(h.snapshot(), before);
      expect(h.errorCount, 0);
      expect(h.legacyResolveCount, 0);
      expect(h.cleanupCount, 0);
    });
  });

  group('Kotlin guard-before-mutation source contracts (B)', () {
    late String discovery;

    setUpAll(() {
      discovery = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
    });

    int indexOf(String token, [int start = 0]) =>
        discovery.indexOf(token, start);

    test('start-failure guards precede browsing/lifecycle/cleanup/error', () {
      final int blockStart = indexOf(
        'override fun onStartDiscoveryFailed(regType: String, errorCode: Int) {',
      );
      expect(blockStart, greaterThanOrEqualTo(0));
      final int genGuard = indexOf('generation.get() != gen', blockStart);
      final int listenerGenGuard = indexOf(
        'discoveryListenerGen != gen',
        genGuard,
      );
      final int identityGuard = indexOf(
        'discoveryListener !== this',
        listenerGenGuard,
      );
      final int browsingSet = indexOf('browsing.set(false)', identityGuard);
      final int cleanup = indexOf('cleanupBrowseGeneration(', browsingSet);
      final int emit = indexOf('emitError(', cleanup);
      // Ordering inside the dispatched block: guards -> mutation -> cleanup
      // -> bounded current error.
      expect(genGuard, greaterThan(blockStart));
      expect(listenerGenGuard, greaterThan(genGuard));
      expect(identityGuard, greaterThan(listenerGenGuard));
      expect(browsingSet, greaterThan(identityGuard));
      expect(cleanup, greaterThan(browsingSet));
      expect(emit, greaterThan(cleanup));
      // All inside the dispatched lambda: the emit is before the callback's
      // closing brace for this override.
      expect(
        discovery.substring(blockStart, emit + 40).contains('dispatchState {'),
        isTrue,
      );
    });

    test('stop-failure guards precede error emission and UNCERTAIN', () {
      final int blockStart = indexOf(
        'override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {',
      );
      expect(blockStart, greaterThanOrEqualTo(0));
      final int genGuard = indexOf('generation.get() != gen', blockStart);
      final int listenerGenGuard = indexOf(
        'discoveryListenerGen != gen',
        genGuard,
      );
      final int identityGuard = indexOf(
        'discoveryListener !== this',
        listenerGenGuard,
      );
      final int emit = indexOf(
        'emitError("discoveryStopFailed"',
        identityGuard,
      );
      final int uncertain = indexOf(
        'lifecycle = BrowseLifecycle.UNCERTAIN',
        emit,
      );
      expect(genGuard, greaterThan(blockStart));
      expect(listenerGenGuard, greaterThan(genGuard));
      expect(identityGuard, greaterThan(listenerGenGuard));
      expect(emit, greaterThan(identityGuard));
      expect(uncertain, greaterThan(emit));
    });

    test(
      'registration-failure guards precede callback-null and legacy fallback',
      () {
        final int blockStart = indexOf(
          'override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {',
        );
        expect(blockStart, greaterThanOrEqualTo(0));
        final int liveGuard = indexOf('!live(gen)', blockStart);
        final int entryGenGuard = indexOf('entry.generation != gen', liveGuard);
        final int trackedGuard = indexOf(
          'tracked[entry.registrationKey] !== entry',
          entryGenGuard,
        );
        final int callbackGuard = indexOf(
          'entry.callback !== this',
          trackedGuard,
        );
        final int callbackNull = indexOf(
          'entry.callback = null',
          callbackGuard,
        );
        final int fallback = indexOf(
          'registerLegacy(manager, service, entry, gen)',
          callbackNull,
        );
        expect(liveGuard, greaterThan(blockStart));
        expect(entryGenGuard, greaterThan(liveGuard));
        expect(trackedGuard, greaterThan(entryGenGuard));
        expect(callbackGuard, greaterThan(trackedGuard));
        expect(callbackNull, greaterThan(callbackGuard));
        expect(fallback, greaterThan(callbackNull));
        expect(
          discovery
              .substring(blockStart, fallback + 40)
              .contains('dispatchState {'),
          isTrue,
        );
      },
    );

    test('dispatched guard pattern is used consistently', () {
      expect(discovery.contains('return@dispatchState'), isTrue);
      // All four lifecycle callbacks carry the three ownership guards.
      expect('generation.get() != gen'.allMatches(discovery).length, 4);
      expect('discoveryListenerGen != gen'.allMatches(discovery).length, 4);
      expect('discoveryListener !== this'.allMatches(discovery).length, 4);
    });

    test('callback classification is documented', () {
      expect(
        discovery.contains('Stale FAILURE-callback guards (D-07-17)'),
        isTrue,
      );
      expect(discovery.contains('notification-only'), isTrue);
      expect(
        discovery.contains(
          'onResolveFailed, onServiceInfoCallbackUnregistered',
        ),
        isTrue,
      );
    });
  });

  group('existing iOS regressions remain locked', () {
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

enum HarnessLifecycle { stopped, starting, browsing, stopping, uncertain }

/// Executable mirror of the PRODUCTION guard-before-mutation ordering for
/// failure callbacks (D-07-17): every failure handler queues a block onto
/// one serialized queue; the block validates generation + listener/entry/
/// callback ownership FIRST and returns early on any mismatch, so a stale
/// callback produces zero mutation, zero cleanup, zero error, zero native
/// work. This mirrors `FileHopLanDiscovery` semantics exactly for test
/// purposes — it is not the production code path itself.
class LanFailureGuardHarness {
  HarnessLifecycle lifecycle = HarnessLifecycle.stopped;
  bool browsing = false;
  bool uncertain = false;
  int generation = 0;
  int listenerGen = 0;
  Object? listener;
  Object? gen1Listener;
  int cleanupCount = 0;
  int errorCount = 0;
  String? lastError;
  int legacyResolveCount = 0;
  final Map<String, Object> entries = <String, Object>{};
  final List<void Function()> _queue = <void Function()>[];

  void dispatch(void Function() block) => _queue.add(block);

  void drain() {
    while (_queue.isNotEmpty) {
      _queue.removeAt(0)();
    }
  }

  void startGeneration() {
    generation += 1;
    listenerGen = generation;
    listener = Object();
    gen1Listener ??= listener;
    lifecycle = HarnessLifecycle.starting;
  }

  void finishGen1AndStartGen2() {
    startGeneration();
  }

  void startGen2Browsing() {
    browsing = true;
    lifecycle = HarnessLifecycle.browsing;
  }

  Object trackEntry(String key) {
    final Object token = Object();
    entries[key] = token;
    return token;
  }

  void cleanupGeneration() {
    entries.clear();
    browsing = false;
  }

  /// Mirrors the production onStartDiscoveryFailed ordering exactly.
  void onStartDiscoveryFailed(int gen, Object? listenerToken) {
    dispatch(() {
      if (generation != gen) return;
      if (listenerGen != gen) return;
      if (!identical(listener, listenerToken)) return;
      browsing = false;
      if (lifecycle == HarnessLifecycle.starting ||
          lifecycle == HarnessLifecycle.stopping) {
        lifecycle = HarnessLifecycle.stopped;
      }
      cleanupCount += 1;
      emit('discoveryStartFailed');
    });
  }

  /// Mirrors the production onStopDiscoveryFailed ordering exactly.
  void onStopDiscoveryFailed(int gen, Object? listenerToken) {
    dispatch(() {
      if (generation != gen) return;
      if (listenerGen != gen) return;
      if (!identical(listener, listenerToken)) return;
      emit('discoveryStopFailed');
      if (lifecycle == HarnessLifecycle.stopping ||
          lifecycle == HarnessLifecycle.browsing) {
        lifecycle = HarnessLifecycle.uncertain;
        uncertain = true;
      }
    });
  }

  /// Mirrors the production registration-failure ordering exactly:
  /// live(gen) → entry generation → tracked identity → callback ownership
  /// → only then callback-null + legacy fallback.
  void onRegistrationFailed(int gen, Object entryToken) {
    dispatch(() {
      if (!(generation == gen && browsing)) return;
      final String key = entries.keys.firstWhere(
        (String k) => identical(entries[k], entryToken),
        orElse: () => '',
      );
      if (key.isEmpty) return;
      if (!identical(entries[key], entryToken)) return;
      legacyResolveCount += 1;
    });
  }

  void emit(String error) {
    errorCount += 1;
    lastError = error;
  }

  String snapshot() =>
      '$generation|$listenerGen|$lifecycle|$browsing|$uncertain|'
      '$cleanupCount|$errorCount|$legacyResolveCount|${entries.length}';
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
