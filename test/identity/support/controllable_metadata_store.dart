import 'package:filehop/identity/errors.dart';
import 'package:filehop/identity/local_identity_metadata_store.dart';
import 'package:filehop/persistence/errors.dart';
import 'package:filehop/persistence/records/persistence_records.dart';

class ControllableLocalIdentityMetadataStore
    implements LocalIdentityMetadataStore {
  LocalIdentityRecord? row;
  bool failWrite = false;
  bool failDelete = false;
  bool failRead = false;
  int readCallCount = 0;
  int insertCallCount = 0;
  int deleteCallCount = 0;

  @override
  Future<LocalIdentityRecord?> read() async {
    readCallCount += 1;
    if (failRead) {
      throw const IdentityException(
        kind: IdentityFailureKind.operationFailure,
        message: 'metadata read failed',
      );
    }
    return row;
  }

  @override
  Future<void> insertIfAbsent(LocalIdentityRecord record) async {
    insertCallCount += 1;
    if (failWrite) {
      throw const IdentityException(
        kind: IdentityFailureKind.operationFailure,
        message: 'metadata write failed',
      );
    }
    if (row != null) {
      throw const PersistenceException(
        kind: PersistenceFailureKind.constraintViolation,
        message: 'local identity already exists',
      );
    }
    row = record;
  }

  @override
  Future<void> delete() async {
    deleteCallCount += 1;
    if (failDelete) {
      throw const IdentityException(
        kind: IdentityFailureKind.operationFailure,
        message: 'metadata delete failed',
      );
    }
    row = null;
  }
}
