import 'lan_path_ownership.dart';

/// Registration-level path-binding outcome (mirrors the Kotlin
/// `PathBindOutcome` as seen through [LanRegistrationPathBindings.bindPath]).
enum LanPathBindOutcome {
  /// First global owner of a new instance: `candidateFound`.
  newInstance,

  /// Additional global owner of an existing instance: `candidateUpdated`
  /// (idempotent metadata refresh, never a second candidate identity).
  existingInstance,

  /// The path was already bound to this instance: no emission.
  duplicateBinding,

  /// Per-registration/per-instance bound reached: deterministic drop.
  pathLimitReached,
}

/// Pathless (no-argument) service-loss outcome (mirrors the Kotlin
/// `PathlessLossOutcome`).
enum LanPathlessLossOutcome {
  /// Zero bindings: stale no-op.
  stale,

  /// Exactly one binding: that path was removed (candidateLost only when
  /// the instance lost its FINAL global owner).
  removedOne,

  /// More than one binding: bounded ambiguous diagnostic, remove NOTHING.
  ambiguous,
}

/// Executable Dart mirror of the Android registration coordinator
/// (D-07-15):
///
/// > one registration = `Map<NativePathKey, FileHopInstanceId>`
///
/// Each native path is INDEPENDENTLY bound to the FileHop discovery
/// instance ID advertised on that path, so one registration can
/// simultaneously represent `{NetworkA → X, NetworkB → Y}`. The global
/// index remains `instanceId → Set<NativePathKey>` and stays consistent
/// with every registration binding. Path keys are runtime-only locator
/// metadata: never peer identity, never persisted.
class LanRegistrationPathBindings {
  LanRegistrationPathBindings({required LanPathOwnership globalOwnership})
    : _global = globalOwnership;

  /// Mirrors `MAX_NATIVE_PATHS_PER_INSTANCE` (D-07-10/D-07-15).
  static const int kMaxNativePathsPerRegistration = 8;

  final LanPathOwnership _global;

  /// The shared global instance → owner-set model (read-only access for
  /// assertions; mutations go through this coordinator).
  LanPathOwnership get globalOwnership => _global;

  /// registrationKey -> { nativePathKey : instanceId }
  final Map<String, Map<String, String>> _bindings =
      <String, Map<String, String>>{};

  bool isTracked(String registrationKey) =>
      _bindings.containsKey(registrationKey);

  Map<String, String> bindingsOf(String registrationKey) {
    final Map<String, String>? map = _bindings[registrationKey];
    if (map == null) {
      return const <String, String>{};
    }
    return Map<String, String>.unmodifiable(map);
  }

  /// Binds [pathKey] to [instanceId] for [registrationKey]. Returns the
  /// emission-relevant outcome plus [lostOld] — true when the SAME path
  /// switched from a previous instance whose FINAL global owner was
  /// removed by this call (→ candidateLost(old) exactly then).
  ///
  /// Cases (prompt §14):
  /// - new path, new instance → newInstance (candidateFound);
  /// - new path, existing instance → existingInstance (candidateUpdated);
  /// - duplicate same binding → duplicateBinding (idempotent, nothing);
  /// - path changes instance → unbind old (lostOld if final), bind new;
  /// - per-registration bound exceeded → pathLimitReached (drop, no evict).
  ({LanPathBindOutcome outcome, bool lostOld}) bindPath({
    required String registrationKey,
    required String pathKey,
    required String instanceId,
  }) {
    final Map<String, String> map = _bindings.putIfAbsent(
      registrationKey,
      () => <String, String>{},
    );
    final String? existingInstance = map[pathKey];
    if (existingInstance == instanceId) {
      return (outcome: LanPathBindOutcome.duplicateBinding, lostOld: false);
    }
    var lostOld = false;
    if (existingInstance != null) {
      // This path switched its TXT instance: unbind only itself.
      map.remove(pathKey);
      lostOld = _global.remove(instanceId: existingInstance, pathKey: pathKey);
    } else if (map.length >= kMaxNativePathsPerRegistration) {
      return (outcome: LanPathBindOutcome.pathLimitReached, lostOld: false);
    }
    final LanPathOutcome outcome = _global.add(
      instanceId: instanceId,
      pathKey: pathKey,
    );
    switch (outcome) {
      case LanPathOutcome.firstOwner:
        map[pathKey] = instanceId;
        return (outcome: LanPathBindOutcome.newInstance, lostOld: lostOld);
      case LanPathOutcome.additionalOwner:
        map[pathKey] = instanceId;
        return (outcome: LanPathBindOutcome.existingInstance, lostOld: lostOld);
      case LanPathOutcome.duplicatePath:
        return (outcome: LanPathBindOutcome.duplicateBinding, lostOld: lostOld);
      case LanPathOutcome.pathLimitReached:
        return (outcome: LanPathBindOutcome.pathLimitReached, lostOld: lostOld);
    }
  }

  /// Removes exactly the identified path binding. Returns true only when
  /// the bound instance lost its FINAL global owner (→ candidateLost);
  /// an unknown/stale path returns false and changes nothing.
  bool unbindPath({required String registrationKey, required String pathKey}) {
    final Map<String, String>? map = _bindings[registrationKey];
    if (map == null || !map.containsKey(pathKey)) {
      return false;
    }
    final String instanceId = map.remove(pathKey)!;
    return _global.remove(instanceId: instanceId, pathKey: pathKey);
  }

  /// Pathless (no-argument) service-loss semantics (D-07-15):
  /// zero bindings → stale; exactly one → remove it (finalLoss true when
  /// the instance lost its final owner → candidateLost); more than one →
  /// ambiguous, remove NOTHING. Distinct from FileHop-owned lifecycle
  /// cleanup, which may remove the whole registration.
  ({LanPathlessLossOutcome outcome, bool finalLoss, String? instanceId})
  pathlessLoss(String registrationKey) {
    final Map<String, String>? map = _bindings[registrationKey];
    if (map == null || map.isEmpty) {
      return (
        outcome: LanPathlessLossOutcome.stale,
        finalLoss: false,
        instanceId: null,
      );
    }
    if (map.length > 1) {
      return (
        outcome: LanPathlessLossOutcome.ambiguous,
        finalLoss: false,
        instanceId: null,
      );
    }
    final String path = map.keys.single;
    final String instanceId = map.remove(path)!;
    final bool finalLoss = _global.remove(
      instanceId: instanceId,
      pathKey: path,
    );
    return (
      outcome: LanPathlessLossOutcome.removedOne,
      finalLoss: finalLoss,
      instanceId: instanceId,
    );
  }

  /// FileHop-owned lifecycle cleanup: removes EVERY path→instance binding
  /// of the registration. Returns the set of instance IDs that lost their
  /// FINAL global owner (each → exactly one candidateLost). Unknown
  /// registrations return an empty set.
  Set<String> cleanupRegistration(String registrationKey) {
    final Map<String, String>? map = _bindings.remove(registrationKey);
    if (map == null) {
      return const <String>{};
    }
    final Set<String> finalLosses = <String>{};
    for (final String path in map.keys.toList()) {
      final String instanceId = map[path]!;
      map.remove(path);
      if (_global.remove(instanceId: instanceId, pathKey: path)) {
        finalLosses.add(instanceId);
      }
    }
    return finalLosses;
  }

  /// Mirrors the Kotlin `correlateResolvedPathLoss` (D-07-16): bounded
  /// ownership-based correlation for a concrete resolved path loss whose
  /// direct registration lookup missed (the registration may still be
  /// indexed under its seed key).
  ///
  /// [registrationKeysOfCurrentGeneration] is the current-generation
  /// registration key list (mirrors `tracked.values` filtering). Exactly
  /// one owner → unbind only that path (`finalLoss` true when the instance
  /// lost its FINAL global owner → candidateLost); zero → stale/unknown,
  /// nothing; more than one (defensive) → ambiguous, remove nothing.
  ({bool removed, bool finalLoss, bool ambiguous}) correlateResolvedPathLoss({
    required List<String> registrationKeysOfCurrentGeneration,
    required String pathKey,
  }) {
    final List<String> matches = registrationKeysOfCurrentGeneration
        .where((String key) => bindingsOf(key).containsKey(pathKey))
        .toList();
    if (matches.length == 1) {
      final bool finalLoss = unbindPath(
        registrationKey: matches.single,
        pathKey: pathKey,
      );
      return (removed: true, finalLoss: finalLoss, ambiguous: false);
    }
    return (removed: false, finalLoss: false, ambiguous: matches.length > 1);
  }

  /// Mirrors the Kotlin `removeBinding` partial-loss removal: removes
  /// exactly one binding and returns the final-loss signal.
  ({bool removed, bool finalLoss}) removeBinding({
    required String registrationKey,
    required String pathKey,
  }) {
    final Map<String, String>? map = _bindings[registrationKey];
    if (map == null || !map.containsKey(pathKey)) {
      return (removed: false, finalLoss: false);
    }
    final String instanceId = map.remove(pathKey)!;
    final bool finalLoss = _global.remove(
      instanceId: instanceId,
      pathKey: pathKey,
    );
    return (removed: true, finalLoss: finalLoss);
  }

  /// Silent seed refinement: the registration's ONLY binding is its own
  /// seed stand-in; it is replaced by the real resolved key. The same
  /// physical path merely became better correlated — no loss signal, no
  /// new-candidate signal. Returns true when a refinement happened.
  bool refineSeedBinding({
    required String registrationKey,
    required String instanceId,
    required String resolvedKey,
  }) {
    final Map<String, String>? map = _bindings[registrationKey];
    if (map == null ||
        map.length != 1 ||
        map[registrationKey] != instanceId ||
        registrationKey == resolvedKey) {
      return false;
    }
    map.remove(registrationKey);
    // The final-loss signal is deliberately ignored: refinement is silent
    // and immediately re-establishes ownership.
    _global.remove(instanceId: instanceId, pathKey: registrationKey);
    _global.add(instanceId: instanceId, pathKey: resolvedKey);
    map[resolvedKey] = instanceId;
    return true;
  }

  void clear() {
    _bindings.clear();
  }
}
