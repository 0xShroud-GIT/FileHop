import 'dart:collection';

/// Frozen Mission 07 one-to-many native LAN path ownership semantics
/// (D-07-10).
///
/// One FileHop ephemeral discovery instance ID may be visible through
/// multiple simultaneous native network paths/interfaces. This class is the
/// canonical pure-Dart reference model for that ownership; the Kotlin and
/// Swift LAN adapters mirror these exact semantics internally (verified by
/// source-contract tests), while the shared candidate identity always
/// remains the single `(lan, instanceId)` key.
///
/// Path keys are native correlation tokens (iOS: native service endpoint;
/// Android: network+name platform-local track key). They are runtime-only:
/// never peer identity, never persisted, never exposed to Dart as identity.
enum LanPathOutcome {
  /// First native owner for this instance: emit `candidateFound`.
  firstOwner,

  /// Additional native owner: emit `candidateUpdated` (idempotent metadata
  /// refresh). Never a second shared candidate identity.
  additionalOwner,

  /// Duplicate callback for an already-owned path: no emission.
  duplicatePath,

  /// Per-instance native path bound reached: drop the new path
  /// deterministically and emit a bounded diagnostic. Never evict an
  /// existing owner.
  pathLimitReached,
}

class LanPathOwnership {
  LanPathOwnership();

  /// D-07-10 bound: maximum simultaneous native paths per LAN instance.
  /// Untrusted/noisy discovery input must not grow ownership unbounded.
  static const int kMaxNativePathsPerInstance = 8;

  final Map<String, Set<String>> _owners = <String, Set<String>>{};

  int get trackedInstances => _owners.length;

  Set<String> ownersOf(String instanceId) {
    final Set<String>? set = _owners[instanceId];
    if (set == null) {
      return const <String>{};
    }
    return UnmodifiableSetView<String>(set);
  }

  bool owns(String instanceId, String pathKey) {
    return _owners[instanceId]?.contains(pathKey) ?? false;
  }

  /// Registers [pathKey] as an owner of [instanceId].
  ///
  /// - [LanPathOutcome.firstOwner]: the instance had no owners before this
  ///   call; the shared lifecycle emits `candidateFound`.
  /// - [LanPathOutcome.additionalOwner]: another path already owned the
  ///   instance; the shared lifecycle emits `candidateUpdated`.
  /// - [LanPathOutcome.duplicatePath]: this exact path already owns the
  ///   instance (duplicate native callback); nothing changes, no emission.
  /// - [LanPathOutcome.pathLimitReached]: the per-instance native path
  ///   bound is exceeded; the new path is dropped deterministically.
  LanPathOutcome add({required String instanceId, required String pathKey}) {
    final Set<String>? existing = _owners[instanceId];
    if (existing != null) {
      if (existing.contains(pathKey)) {
        return LanPathOutcome.duplicatePath;
      }
      if (existing.length >= kMaxNativePathsPerInstance) {
        return LanPathOutcome.pathLimitReached;
      }
    }
    final bool wasEmpty = existing == null || existing.isEmpty;
    _owners.putIfAbsent(instanceId, () => <String>{}).add(pathKey);
    return wasEmpty
        ? LanPathOutcome.firstOwner
        : LanPathOutcome.additionalOwner;
  }

  /// Removes [pathKey] from [instanceId].
  ///
  /// Returns `true` only when the FINAL owner was removed, i.e. only then
  /// may the shared lifecycle emit `candidateLost(instanceId)`. Partial
  /// loss (another owner remains) returns `false` and emits nothing.
  /// An unknown/stale path removal returns `false` and changes nothing.
  bool remove({required String instanceId, required String pathKey}) {
    final Set<String>? set = _owners[instanceId];
    if (set == null || !set.remove(pathKey)) {
      return false;
    }
    if (set.isEmpty) {
      _owners.remove(instanceId);
      return true;
    }
    return false;
  }

  void clear() {
    _owners.clear();
  }
}
