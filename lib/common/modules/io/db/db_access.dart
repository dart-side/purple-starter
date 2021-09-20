import 'dart:async';

import 'package:fpdart/fpdart.dart';
import 'package:functional_starter/common/extensions/extensions.dart';
import 'package:functional_starter/common/helpers/try_task.dart';
import 'package:functional_starter/common/models/failure.dart';
import 'package:functional_starter/common/modules/io/db/db_path_manager.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

typedef DbCallbackUnsafe<T> = Future<void> Function(
  Database db,
  StoreRef<T, Map<String, Object?>> store,
);

mixin DbAccess {
  static StoreRef<String, Map<String, Object?>> _mkStore(
    String name,
  ) =>
      stringMapStoreFactory.store(name);

  static Future<Database> _mkDb(
    String path,
  ) =>
      databaseFactoryIo.openDatabase(path);

  // TODO: -- Make client close anyway, using match instead of flatMap
  static TaskEither<Failure, Unit> perform<T>(
    String dbPath,
    StoreRef<T, Map<String, Object?>> store,
    DbCallbackUnsafe<T> f,
  ) =>
      tryTask(() => _mkDb(dbPath)).flatMap(
        (db) => tryTask(() => f(db, store)).flatMap(
          (_) => TaskEither.fromTask(Task(db.close).asUnit()),
        ),
      );

  static TaskEither<Failure, Unit> performDefault(
    String dbName,
    String storeName,
    DbCallbackUnsafe<String> f,
  ) =>
      DbPathManager.getPath(dbName).flatMap(
        (dbPath) => perform(dbPath, _mkStore(storeName), f),
      );

  Stream<List<RecordSnapshot<T, Map<String, Object?>>>> stream<T>(
    String dbPath,
    StoreRef<T, Map<String, Object?>> store, {
    Finder? finder,
  }) async* {
    final db = await _mkDb(dbPath);

    StreamSubscription<List<RecordSnapshot<T, Map<String, Object?>>>>?
        subscription;
    StreamController<List<RecordSnapshot<T, Map<String, Object?>>>>? controller;

    controller = StreamController(
      onCancel: () {
        subscription?.cancel();
        controller?.close();
        db.close();
      },
    );

    if (!controller.isClosed) {
      subscription = store.query(finder: finder).onSnapshots(db).listen(
            controller.add,
            onDone: controller.close,
            onError: controller.addError,
          );
    }

    yield* controller.stream;
  }

  Stream<List<RecordSnapshot<String, Map<String, Object?>>>> streamDefault(
    String dbName,
    String storeName, {
    Finder? finder,
  }) async* {
    final dbPath = await DbPathManager.getPath(dbName).run();
    yield* dbPath.match(
      (failure) => Stream.error(failure.exception, failure.stackTrace),
      (path) => stream(path, _mkStore(storeName)),
    );
  }
}