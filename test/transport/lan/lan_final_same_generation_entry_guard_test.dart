import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mission 07 FINAL same-generation stale-entry guard contracts (D-07-18).
///
/// Evidence classes:
/// - A: the executable harness below mirrors the production rule exactly:
///   an async callback carrying a `Tracked` entry is valid only when the
///   browse generation is current AND the entry is still the object stored
///   under its registration key (`tracked[key] === entry`). Generation
///   validity alone is NOT sufficient — a registration removed or replaced
///   in the SAME generation is a different lifecycle and its callbacks are
///   dropped. No sleeps; deterministic queue drain.
/// - B: Kotlin source contracts lock the guard ordering in
///   `publishResolved` and `handlePathlessLoss`.
/// - C: real NSD callback ordering remains NOT_RUN on the device checklists.
void main() {
  const String instanceX = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const String instanceY = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  group('same-generation detached-entry guard (D-07-18 §16/19/20)', () {
    test('detached current-generation update is dropped; no resurrection', () {
      final h = LanEntryGateHarness();
      h.startBrowsing();
      final Object oldEntry = h.track('K');
      // oldEntry owns A→X.
      h.bindPath(oldEntry, 'networkA|FileHop', instanceX);
      // An update for oldEntry (e.g. refresh / second path) is queued.
      h.submitPublish(oldEntry, 'networkB|FileHop', instanceX);
      // The path/service is lost: oldEntry removed, X becomes lost — but
      // the generation stays current.
      h.untrack('K', emitLost: true);
      expect(h.lostCount, 1);
      expect(h.generation, 1);
      expect(h.browsing, isTrue);
      final before = h.snapshot();
      h.drain();
      expect(h.snapshot(), before);
      expect(h.ownersOf(instanceX), isEmpty, reason: 'no resurrection');
      expect(h.foundCount, 1, reason: 'only the setup bind emitted found');
      expect(h.updatedCount, 0);
    });

    test('detached ServiceInfo update cannot resurrect a candidate', () {
      final h = LanEntryGateHarness();
      h.startBrowsing();
      final Object oldEntry = h.track('K');
      h.bindPath(oldEntry, 'networkA|FileHop', instanceX);
      // onServiceUpdated result for oldEntry is queued...
      h.submitPublish(oldEntry, 'networkB|FileHop', instanceX);
      // ...then the service is lost and the entry detached (same generation).
      h.untrack('K', emitLost: true);
      h.drain();
      expect(h.ownersOf(instanceX), isEmpty);
      expect(h.foundCount, 1, reason: 'only the setup bind emitted found');
      expect(h.updatedCount, 0);
    });

    test('detached legacy resolve cannot resurrect ownership', () {
      final h = LanEntryGateHarness();
      h.startBrowsing();
      final Object oldEntry = h.track('K');
      h.bindPath(oldEntry, 'networkA|FileHop', instanceX);
      // Queued legacy resolve result arrives for a detached entry.
      h.submitPublish(oldEntry, 'networkB|FileHop', instanceX);
      h.untrack('K', emitLost: true);
      h.drain();
      expect(h.ownersOf(instanceX), isEmpty);
      expect(h.foundCount, 1, reason: 'only the setup bind emitted found');
    });
  });

  group('same-key replacement (D-07-18 §17/22)', () {
    test('old callback cannot act on the replacement lifecycle', () {
      final h = LanEntryGateHarness();
      h.startBrowsing();
      final Object oldEntry = h.track('K');
      h.submitPublish(oldEntry, 'networkA|FileHop', instanceX);
      // oldEntry is removed and K is re-registered: a NEW lifecycle.
      h.untrack('K');
      final Object newEntry = h.track('K');
      h.drain();
      // The old callback was dropped: no binding, no owner, no event.
      expect(h.ownersOf(instanceX), isEmpty);
      expect(h.foundCount, 0);
      expect(h.updatedCount, 0);
      expect(identical(h.entryFor('K'), newEntry), isTrue);
      expect(identical(h.entryFor('K'), oldEntry), isFalse);
    });

    test(
      'replacement with new bindings stays untouched by the old callback',
      () {
        final h = LanEntryGateHarness();
        h.startBrowsing();
        final Object oldEntry = h.track('K');
        h.submitPublish(oldEntry, 'networkA|FileHop', instanceX);
        h.untrack('K');
        final Object newEntry = h.track('K');
        // The replacement owns B→Y before the old callback drains.
        h.bindPath(newEntry, 'networkB|FileHop', instanceY);
        h.drain();
        // newEntry's B→Y binding untouched; X never resurrected.
        expect(h.ownersOf(instanceX), isEmpty);
        expect(h.ownersOf(instanceY), <String>{'networkB|FileHop'});
        expect(h.foundCount, 1, reason: 'only the newEntry bind emitted');
        expect(h.updatedCount, 0);
      },
    );
  });

  group('current-entry positive control (D-07-18 §18)', () {
    test('a current tracked entry still publishes normally', () {
      final h = LanEntryGateHarness();
      h.startBrowsing();
      final Object entry = h.track('K');
      h.submitPublish(entry, 'networkA|FileHop', instanceX);
      h.drain();
      expect(h.ownersOf(instanceX), <String>{'networkA|FileHop'});
      expect(h.foundCount, 1);
      expect(h.lostCount, 0);
    });

    test('a second path on a current entry updates without a new found', () {
      final h = LanEntryGateHarness();
      h.startBrowsing();
      final Object entry = h.track('K');
      h.submitPublish(entry, 'networkA|FileHop', instanceX);
      h.drain();
      h.submitPublish(entry, 'networkB|FileHop', instanceX);
      h.drain();
      expect(h.ownersOf(instanceX).length, 2);
      expect(h.foundCount, 1);
      expect(h.updatedCount, 1);
    });
  });

  group('detached pathless loss (D-07-18 §21)', () {
    test('late pathless loss for a detached entry is a harmless no-op', () {
      final h = LanEntryGateHarness();
      h.startBrowsing();
      final Object oldEntry = h.track('K');
      h.bindPath(oldEntry, 'networkA|FileHop', instanceX);
      h.submitPathlessLoss(oldEntry);
      // The entry is removed first (its binding and owner are cleaned).
      h.untrack('K', emitLost: true);
      expect(h.lostCount, 1);
      h.drain();
      // The detached loss callback did nothing: no double candidateLost,
      // no map mutation.
      expect(h.lostCount, 1);
      expect(h.ownersOf(instanceX), isEmpty);
      expect(h.bindingsOf('K'), isEmpty);
    });
  });

  group('Kotlin source contracts (B)', () {
    late String discovery;

    setUpAll(() {
      discovery = locate(
        'android/app/src/main/kotlin/app/filehop/filehop/FileHopLanDiscovery.kt',
      ).readAsStringSync();
    });

    int indexOf(String token, [int start = 0]) =>
        discovery.indexOf(token, start);

    test(
      'publishResolved guard ordering: live → entry gen → identity → mutate',
      () {
        final int fnStart = indexOf('private fun publishResolved(');
        expect(fnStart, greaterThanOrEqualTo(0));
        final int live = indexOf('if (!live(gen)) return', fnStart);
        final int entryGen = indexOf('entry.generation != gen', live);
        final int identity = indexOf(
          'tracked[entry.registrationKey] !== entry',
          entryGen,
        );
        final int serviceType = indexOf(
          'serviceTypeMatches(info.serviceType)',
          identity,
        );
        final int parse = indexOf('parseTxt(info.attributes)', serviceType);
        final int bind = indexOf(
          'bindPath(entry, resolved, instanceId, gen)',
          parse,
        );
        final int emit = indexOf('emitCandidate(', bind);
        expect(live, greaterThan(fnStart));
        expect(entryGen, greaterThan(live));
        expect(identity, greaterThan(entryGen));
        expect(serviceType, greaterThan(identity));
        expect(parse, greaterThan(serviceType));
        expect(bind, greaterThan(parse));
        expect(emit, greaterThan(bind));
      },
    );

    test(
      'pathless-loss guard ordering: live → entry gen → identity → removal',
      () {
        final int fnStart = indexOf('private fun handlePathlessLoss(');
        expect(fnStart, greaterThanOrEqualTo(0));
        final int live = indexOf(
          'if (!live(gen)) return PathlessLossOutcome.STALE',
          fnStart,
        );
        final int entryGen = indexOf('entry.generation != gen', live);
        final int identity = indexOf(
          'tracked[entry.registrationKey] !== entry',
          entryGen,
        );
        final int empty = indexOf('entry.pathOwners.isEmpty()', identity);
        final int sizeMany = indexOf('entry.pathOwners.size > 1', empty);
        final int remove = indexOf('entry.pathOwners.remove(path)', sizeMany);
        expect(live, greaterThan(fnStart));
        expect(entryGen, greaterThan(live));
        expect(identity, greaterThan(entryGen));
        expect(empty, greaterThan(identity));
        expect(sizeMany, greaterThan(empty));
        expect(remove, greaterThan(sizeMany));
      },
    );

    test('object identity is required, not key containment', () {
      // The identity form `!==` guards all three entry-carrying sites
      // (publishResolved, handlePathlessLoss, registration-failure).
      expect(
        'tracked[entry.registrationKey] !== entry'.allMatches(discovery).length,
        3,
      );
      expect(discovery.contains('entry.callback !== this'), isTrue);
      expect(
        discovery.contains('tracked.containsKey(entry.registrationKey)'),
        isFalse,
        reason: 'key containment alone must never substitute identity',
      );
      expect(
        discovery.contains('Same-generation entry identity (D-07-18)'),
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

/// Executable mirror of the PRODUCTION same-generation entry guard
/// (D-07-18): callbacks carrying an entry token execute on one serialized
/// queue and are dropped unless BOTH the generation is current AND the
/// token is still the object stored under its registration key. This
/// mirrors `FileHopLanDiscovery` semantics exactly for test purposes —
/// it is not the production code path itself.
class LanEntryGateHarness {
  int generation = 0;
  bool browsing = false;

  /// tracked: registrationKey -> entry token (object identity).
  final Map<String, Object> _entries = <String, Object>{};

  /// entry token -> (pathKey -> instanceId).
  final Map<Object, Map<String, String>> _pathOwnersByEntry =
      <Object, Map<String, String>>{};

  /// global: instanceId -> set of path keys.
  final Map<String, Set<String>> _globalOwners = <String, Set<String>>{};

  final List<void Function()> _queue = <void Function()>[];
  int foundCount = 0;
  int updatedCount = 0;
  int lostCount = 0;

  void startBrowsing() {
    generation = 1;
    browsing = true;
  }

  Object track(String key) {
    final Object token = Object();
    _entries[key] = token;
    _pathOwnersByEntry[token] = <String, String>{};
    return token;
  }

  Object? entryFor(String key) => _entries[key];

  Set<String> ownersOf(String instanceId) =>
      Set<String>.unmodifiable(_globalOwners[instanceId] ?? <String>{});

  Map<String, String> bindingsOf(String key) {
    final Object? token = _entries[key];
    if (token == null) {
      return const <String, String>{};
    }
    return Map<String, String>.unmodifiable(
      _pathOwnersByEntry[token] ?? const <String, String>{},
    );
  }

  /// Direct (non-queued) binding used to set up state: mirrors bindPath.
  void bindPath(Object token, String pathKey, String instanceId) {
    final Map<String, String> map = _pathOwnersByEntry[token]!;
    if (map.containsKey(pathKey)) return;
    final bool first = !(_globalOwners[instanceId]?.isNotEmpty ?? false);
    _globalOwners.putIfAbsent(instanceId, () => <String>{}).add(pathKey);
    map[pathKey] = instanceId;
    if (first) {
      foundCount += 1;
    } else {
      updatedCount += 1;
    }
  }

  /// Removes the registration and every owned path (mirrors
  /// cleanupRegistration / handleLost correlated removal).
  void untrack(String key, {bool emitLost = false}) {
    final Object? token = _entries.remove(key);
    if (token == null) return;
    final Map<String, String>? map = _pathOwnersByEntry.remove(token);
    if (map == null) return;
    for (final String path in map.keys.toList()) {
      final String instanceId = map[path]!;
      map.remove(path);
      final Set<String>? owners = _globalOwners[instanceId];
      if (owners != null) {
        owners.remove(path);
        if (owners.isEmpty) {
          _globalOwners.remove(instanceId);
          if (emitLost) lostCount += 1;
        }
      }
    }
  }

  /// Mirrors the production publishResolved guard ordering exactly:
  /// live(gen) → entry.generation → tracked[key] === entry → then
  /// parse/bind/emit.
  void submitPublish(Object entryToken, String pathKey, String instanceId) {
    final int gen = generation;
    _queue.add(() {
      if (!(generation == gen && browsing)) return;
      final String key = _entries.entries
          .firstWhere(
            (MapEntry<String, Object> e) => identical(e.value, entryToken),
            orElse: () => MapEntry<String, Object>('', Object()),
          )
          .key;
      if (key.isEmpty) return;
      if (!identical(_entries[key], entryToken)) return;
      bindPath(entryToken, pathKey, instanceId);
    });
  }

  /// Mirrors the production handlePathlessLoss guard ordering exactly.
  void submitPathlessLoss(Object entryToken) {
    final int gen = generation;
    _queue.add(() {
      if (!(generation == gen && browsing)) return;
      final String key = _entries.entries
          .firstWhere(
            (MapEntry<String, Object> e) => identical(e.value, entryToken),
            orElse: () => MapEntry<String, Object>('', Object()),
          )
          .key;
      if (key.isEmpty) return;
      if (!identical(_entries[key], entryToken)) return;
      final Map<String, String> map = _pathOwnersByEntry[entryToken]!;
      if (map.isEmpty) return;
      if (map.length > 1) return; // ambiguous: remove none (not exercised)
      final String path = map.keys.single;
      untrack(key, emitLost: true);
    });
  }

  void drain() {
    while (_queue.isNotEmpty) {
      _queue.removeAt(0)();
    }
  }

  String snapshot() =>
      '$generation|$browsing|$foundCount|$updatedCount|$lostCount|'
      '${_entries.length}|${_globalOwners.length}';
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
