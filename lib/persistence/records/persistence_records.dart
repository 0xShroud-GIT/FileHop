// Persistence DTOs. Separate from Mission 03 live domain entities.

class LocalIdentityRecord {
  const LocalIdentityRecord({
    required this.publicIdentityKey,
    required this.identityFingerprint,
    required this.keyStorageVersion,
    required this.createdAtUtcMs,
    this.wrappedKeyRef,
  });

  final List<int> publicIdentityKey;
  final String identityFingerprint;

  /// Metadata for a later wrapped-key store. Not a raw private key.
  final String? wrappedKeyRef;
  final int keyStorageVersion;
  final int createdAtUtcMs;
}

class PeerRecord {
  const PeerRecord({
    required this.fingerprint,
    required this.lastCapabilities,
    this.peerId,
    this.lastKnownDisplayName,
    this.lastSeenUtcMs,
  });

  final int? peerId;
  final String fingerprint;
  final String? lastKnownDisplayName;
  final int? lastSeenUtcMs;
  final List<String> lastCapabilities;
}

class TrustRecordRow {
  const TrustRecordRow({
    required this.fingerprint,
    required this.state,
    required this.verificationMethod,
    required this.createdAtUtcMs,
    required this.updatedAtUtcMs,
    this.localNote,
  });

  final String fingerprint;
  final String state;
  final String verificationMethod;
  final int createdAtUtcMs;
  final int updatedAtUtcMs;
  final String? localNote;
}

class ShareSessionRecord {
  const ShareSessionRecord({
    required this.shareSessionId,
    required this.peerFingerprint,
    required this.direction,
    required this.createdAtUtcMs,
    this.terminalResult,
  });

  final String shareSessionId;
  final String peerFingerprint;
  final String direction;
  final int createdAtUtcMs;
  final String? terminalResult;
}

class TransferRecord {
  const TransferRecord({
    required this.transferId,
    required this.shareSessionId,
    required this.peerFingerprint,
    required this.direction,
    required this.state,
    required this.createdAtUtcMs,
    required this.updatedAtUtcMs,
  });

  final String transferId;
  final String shareSessionId;
  final String peerFingerprint;
  final String direction;
  final String state;
  final int createdAtUtcMs;
  final int updatedAtUtcMs;
}

class TransferItemRecord {
  const TransferItemRecord({
    required this.itemId,
    required this.transferId,
    required this.logicalType,
    required this.displayName,
    required this.expectedLength,
    required this.bytesVerified,
    required this.state,
    this.relativePath,
    this.sourceHandle,
    this.expectedFinalHash,
    this.actualFinalHash,
  });

  final String itemId;
  final String transferId;
  final String logicalType;
  final String displayName;
  final String? relativePath;
  final String? sourceHandle;
  final int expectedLength;
  final int bytesVerified;
  final String? expectedFinalHash;
  final String? actualFinalHash;
  final String state;
}

class TransferCheckpointRecord {
  const TransferCheckpointRecord({
    required this.itemId,
    required this.transferId,
    required this.verifiedLocalByteOffset,
    required this.sourceIdentity,
    required this.destinationPartialIdentity,
    required this.checkpointVersion,
    required this.updatedAtUtcMs,
  });

  final String itemId;
  final String transferId;
  final int verifiedLocalByteOffset;
  final String sourceIdentity;
  final String destinationPartialIdentity;
  final int checkpointVersion;
  final int updatedAtUtcMs;
}

class ActivityRecord {
  const ActivityRecord({
    required this.activityId,
    required this.kind,
    required this.summary,
    required this.createdAtUtcMs,
    this.peerFingerprint,
    this.relatedId,
  });

  final String activityId;
  final String kind;
  final String? peerFingerprint;
  final String? relatedId;
  final String summary;
  final int createdAtUtcMs;
}

class ScreenHistoryRecord {
  const ScreenHistoryRecord({
    required this.screenSessionId,
    required this.peerFingerprint,
    required this.role,
    required this.startedAtUtcMs,
    required this.terminalResult,
    this.endedAtUtcMs,
  });

  final String screenSessionId;
  final String peerFingerprint;
  final String role;
  final int startedAtUtcMs;
  final int? endedAtUtcMs;
  final String terminalResult;
}
