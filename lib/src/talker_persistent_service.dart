import 'dart:io';

import 'package:collection/collection.dart';
import 'package:hive_ce/hive.dart';
import 'package:talker/talker.dart';
import 'package:talker_persistent/hive/hive_adapters.dart';
import 'package:talker_persistent/src/adapters/talker_data.dart';

class TalkerPersistent {
  static TalkerPersistent? _instance;

  TalkerPersistent._();
  static TalkerPersistent get instance => _instance ??= TalkerPersistent._();

  bool _isInitialized = false;

  Box<TalkerDataPersistent>? _box;

  bool get isInitialized {
    assert(_isInitialized, """
  TalkerPersistent is not initialized.
  ```dart
  void main() async {
    await TalkerPersistent().initialize(path: 'path/to/your/hive/directory');
  }
 ```
  """);
    return _isInitialized;
  }

  Map<String, List<TalkerDataPersistent>> _logs = {};

  Future<void> initialize({String? path, required Set<String> logNames}) async {
    final currentDir = Directory.current.path;
    Hive
      ..init(path ?? currentDir)
      ..registerAdapter(TalkerDataPersistentAdapter())
      ..registerAdapter(LogLevelPersistentAdapter());

    _box = await Hive.openBox<TalkerDataPersistent>('talker_history');
    _isInitialized = true;

    // Initialize empty lists for all log names
    _logs = {};
    for (final logName in logNames) {
      _logs[logName] = [];
    }

    // Load existing logs from Hive
    final existingLogs = _box!.values.groupListsBy((e) => e.logName);
    _logs.addAll(existingLogs);
  }

  void write({required TalkerData data, required String logName, required int maxCapacity}) {
    if (!_logs.containsKey(logName)) {
      _logs[logName] = [];
    }

    if (_logs[logName]!.length >= maxCapacity) {
      _box?.deleteAt(0);
      _logs[logName]!.removeAt(0);
    }

    final adapter = TalkerDataPersistent.fromTalkerData(data: data, id: logName);
    _box?.add(adapter);
    _logs[logName]!.add(adapter);
  }

  void clean({required String logName}) {
    if (_logs.containsKey(logName)) {
      _box!.deleteAll(_logs[logName]!.map((e) => e.key));
      _logs[logName]?.clear();
    }
  }

  List<TalkerData> getLogs({required String logName}) {
    return _logs[logName]?.map((e) => e.toTalkerData()).toList() ?? [];
  }

  Future<void> dispose() async {
    if (_isInitialized) {
      try {
        await _box?.close();
        _box = null;
        _isInitialized = false;
        _logs.clear();
      } catch (e) {
        rethrow;
      }
    }
  }

  /// Dispose global de recursos do sistema de logging persistente
  static Future<void> disposeGlobalResources() async {}
}
