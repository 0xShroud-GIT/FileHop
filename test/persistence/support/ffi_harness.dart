import 'dart:io';

import 'package:filehop/persistence/persistence.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _ffiReady = false;

void ensureSqfliteFfi() {
  if (_ffiReady) {
    return;
  }
  sqfliteFfiInit();
  _ffiReady = true;
}

Future<({FileHopDatabase db, File file, FileHopStores stores})> openTempDb({
  int targetVersion = kFileHopSchemaVersion,
  List<SchemaMigration> migrations = const <SchemaMigration>[],
}) async {
  ensureSqfliteFfi();
  final Directory dir = await Directory.systemTemp.createTemp('filehop-m04-');
  final File file = File('${dir.path}/filehop.sqlite');
  final FileHopDatabase db = await FileHopDatabase.open(
    factory: databaseFactoryFfi,
    path: file.path,
    targetVersion: targetVersion,
    migrations: migrations,
  );
  return (db: db, file: file, stores: FileHopStores(db.raw));
}

Future<void> deleteTempDb(File file) async {
  final Directory dir = file.parent;
  if (await file.exists()) {
    await file.delete();
  }
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}

const String kFpA = 'VYQWYLXVER5DPAWBGXX2E6ND4TG4MEEUE4HV2K7FRRRAJN5GCLEQ';
const String kFpB = 'P3XFQAG5ZU5TZSP5AR4DDTMFG3R4H5L7ITLUN5IV3KJ7ASHOT2IQ';
const String kShareId = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const String kTransferId = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const String kItemId = 'cccccccccccccccccccccccccccccccc';
const String kActivityId = 'dddddddddddddddddddddddddddddddd';
const String kScreenId = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee';
const int kTs = 1700000000000;
