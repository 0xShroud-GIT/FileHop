import '../persistence/records/persistence_records.dart';
import '../persistence/stores/filehop_stores.dart';

abstract class LocalIdentityMetadataStore {
  Future<LocalIdentityRecord?> read();

  /// Inserts the singleton LocalIdentity row. Must not replace.
  /// Throws [PersistenceException] constraintViolation if the row exists.
  Future<void> insertIfAbsent(LocalIdentityRecord record);

  Future<void> delete();
}

class SqliteLocalIdentityMetadataStore implements LocalIdentityMetadataStore {
  SqliteLocalIdentityMetadataStore(this._stores);

  final FileHopStores _stores;

  @override
  Future<LocalIdentityRecord?> read() => _stores.getLocalIdentity();

  @override
  Future<void> insertIfAbsent(LocalIdentityRecord record) {
    return _stores.insertLocalIdentityIfAbsent(record);
  }

  @override
  Future<void> delete() => _stores.deleteLocalIdentity();
}
