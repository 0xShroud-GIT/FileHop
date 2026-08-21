/// Production FileHop schema version. There is no released schema v0 or v2.
const int kFileHopSchemaVersion = 1;

/// SQLite DDL for schema v1. Enums are stable strings, never Dart indexes.
const List<String> kSchemaV1Statements = <String>[
  '''
CREATE TABLE local_identity (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  public_identity_key BLOB NOT NULL,
  identity_fingerprint TEXT NOT NULL UNIQUE,
  wrapped_key_ref TEXT,
  key_storage_version INTEGER NOT NULL,
  created_at_utc_ms INTEGER NOT NULL
)
''',
  '''
CREATE TABLE peers (
  peer_id INTEGER PRIMARY KEY AUTOINCREMENT,
  fingerprint TEXT NOT NULL UNIQUE,
  last_known_display_name TEXT,
  last_seen_utc_ms INTEGER,
  last_capabilities_json TEXT NOT NULL DEFAULT '[]'
)
''',
  '''
CREATE TABLE trust_records (
  fingerprint TEXT PRIMARY KEY,
  state TEXT NOT NULL CHECK (state IN ('TRUSTED', 'BLOCKED')),
  verification_method TEXT NOT NULL CHECK (verification_method IN ('QR', 'SAS', 'USER_BLOCK')),
  created_at_utc_ms INTEGER NOT NULL,
  updated_at_utc_ms INTEGER NOT NULL,
  local_note TEXT
)
''',
  '''
CREATE TABLE share_sessions (
  share_session_id TEXT PRIMARY KEY,
  peer_fingerprint TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('outgoing', 'incoming')),
  created_at_utc_ms INTEGER NOT NULL,
  terminal_result TEXT CHECK (
    terminal_result IS NULL OR terminal_result IN ('COMPLETED', 'REJECTED', 'CANCELLED', 'FAILED')
  )
)
''',
  '''
CREATE TABLE transfers (
  transfer_id TEXT PRIMARY KEY,
  share_session_id TEXT NOT NULL,
  peer_fingerprint TEXT NOT NULL,
  direction TEXT NOT NULL CHECK (direction IN ('outgoing', 'incoming')),
  state TEXT NOT NULL,
  created_at_utc_ms INTEGER NOT NULL,
  updated_at_utc_ms INTEGER NOT NULL,
  FOREIGN KEY (share_session_id) REFERENCES share_sessions(share_session_id) ON DELETE RESTRICT
)
''',
  '''
CREATE TABLE transfer_items (
  item_id TEXT PRIMARY KEY,
  transfer_id TEXT NOT NULL,
  logical_type TEXT NOT NULL,
  display_name TEXT NOT NULL,
  relative_path TEXT,
  source_handle TEXT,
  expected_length INTEGER NOT NULL CHECK (expected_length >= 0),
  bytes_verified INTEGER NOT NULL CHECK (bytes_verified >= 0),
  expected_final_hash TEXT,
  actual_final_hash TEXT,
  state TEXT NOT NULL,
  FOREIGN KEY (transfer_id) REFERENCES transfers(transfer_id) ON DELETE RESTRICT,
  UNIQUE (item_id, transfer_id),
  CHECK (bytes_verified <= expected_length),
  CHECK (
    state != 'COMPLETED'
    OR (
      bytes_verified = expected_length
      AND expected_final_hash IS NOT NULL
      AND actual_final_hash IS NOT NULL
      AND expected_final_hash = actual_final_hash
    )
  )
)
''',
  '''
CREATE TABLE transfer_checkpoints (
  item_id TEXT PRIMARY KEY,
  transfer_id TEXT NOT NULL,
  verified_local_byte_offset INTEGER NOT NULL CHECK (verified_local_byte_offset >= 0),
  source_identity TEXT NOT NULL,
  destination_partial_identity TEXT NOT NULL,
  checkpoint_version INTEGER NOT NULL,
  updated_at_utc_ms INTEGER NOT NULL,
  FOREIGN KEY (item_id) REFERENCES transfer_items(item_id) ON DELETE RESTRICT,
  FOREIGN KEY (transfer_id) REFERENCES transfers(transfer_id) ON DELETE RESTRICT,
  FOREIGN KEY (item_id, transfer_id) REFERENCES transfer_items(item_id, transfer_id) ON DELETE RESTRICT
)
''',
  '''
CREATE TABLE activity_records (
  activity_id TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  peer_fingerprint TEXT,
  related_id TEXT,
  summary TEXT NOT NULL,
  created_at_utc_ms INTEGER NOT NULL
)
''',
  '''
CREATE TABLE screen_history (
  screen_session_id TEXT PRIMARY KEY,
  peer_fingerprint TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('sender', 'receiver')),
  started_at_utc_ms INTEGER NOT NULL,
  ended_at_utc_ms INTEGER,
  terminal_result TEXT NOT NULL CHECK (
    terminal_result IN ('CLOSED', 'REJECTED', 'CANCELLED', 'FAILED', 'INTERRUPTED')
  )
)
''',
  'CREATE INDEX idx_transfers_share ON transfers(share_session_id)',
  'CREATE INDEX idx_items_transfer ON transfer_items(transfer_id)',
  'CREATE INDEX idx_activity_created ON activity_records(created_at_utc_ms)',
];

const List<String> kSchemaV1Tables = <String>[
  'local_identity',
  'peers',
  'trust_records',
  'share_sessions',
  'transfers',
  'transfer_items',
  'transfer_checkpoints',
  'activity_records',
  'screen_history',
];
