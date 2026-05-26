import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math;

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as path;
import 'package:talker/talker.dart';
import 'package:talker_dio_logger/dio_logs.dart';
import 'package:talker_persistent/src/talker_persistent_service.dart';

const String _extension = 'log';

// An entry starts with an ISO-8601 timestamp (YYYY-MM-DDTHH:MM:SS...)
final _entryStartPattern = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}');

List<String> _splitLogEntries(String content) {
  final lines = content.split('\n');
  final logs = <String>[];
  var current = <String>[];
  for (final line in lines) {
    if (_entryStartPattern.hasMatch(line)) {
      if (current.isNotEmpty) logs.add(current.join('\n'));
      current = [line];
    } else if (current.isNotEmpty) {
      current.add(line);
    }
  }
  if (current.isNotEmpty) logs.add(current.join('\n'));
  return logs;
}

class _LogFileManager {
  final String filePath;
  final bool saveAllLogs;
  final int retentionDays;
  final int? maxFileSize;

  File? logFile;
  int currentLogCount = 0;
  String? currentDate;
  String? baseName;

  _LogFileManager({
    required this.filePath,
    required this.saveAllLogs,
    this.retentionDays = 3,
    this.maxFileSize,
  });

  Future<void> initialize() async {
    baseName = path.basenameWithoutExtension(filePath);
    if (baseName == null || baseName!.isEmpty) baseName = 'log';

    if (saveAllLogs) {
      final now = DateTime.now();
      currentDate = _dateString(now);
      final basePath = path.dirname(filePath);
      logFile = File(path.join(basePath, '$baseName-$currentDate.$_extension'));
      await _deleteOldFiles();
    } else {
      logFile = File(filePath);
    }

    try {
      await logFile!.parent.create(recursive: true);
    } catch (_) {}

    if (await logFile!.exists()) {
      try {
        final content = await logFile!.readAsString();
        currentLogCount = _splitLogEntries(content).length;
      } catch (_) {
        currentLogCount = 0;
      }
    } else {
      try {
        await logFile!.writeAsString('');
      } catch (_) {}
      currentLogCount = 0;
    }
  }

  String _dateString(DateTime dt) => '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Future<void> _deleteOldFiles() async {
    if (baseName == null) return;
    final basePath = logFile?.parent.path;
    if (basePath == null) return;
    try {
      final dir = Directory(basePath);
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(Duration(days: retentionDays));
      final files = await dir.list().toList();
      for (final f in files) {
        if (f is! File) continue;
        if (!f.path.contains(baseName!) || !f.path.endsWith('.$_extension')) continue;
        final match = RegExp(r'(\d{4})-(\d{2})-(\d{2})').firstMatch(f.path);
        if (match == null) continue;
        final fileDate = DateTime(
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        );
        if (fileDate.isBefore(cutoff)) await f.delete();
      }
    } catch (_) {}
  }

  Future<void> write(List<String> logs) async {
    if (logFile == null || logs.isEmpty) return;

    if (saveAllLogs) {
      final today = _dateString(DateTime.now());
      if (currentDate != today) {
        currentDate = today;
        final basePath = logFile!.parent.path;
        logFile = File(path.join(basePath, '$baseName-$currentDate.$_extension'));
        currentLogCount = 0;
        await _deleteOldFiles();
      }
    }

    final content = '${logs.join('\n')}\n';
    final newLogCount = _splitLogEntries(content).length;

    if (maxFileSize != null) {
      try {
        if (await logFile!.exists() && await logFile!.length() + content.length > maxFileSize!) {
          await _rotateBySize();
        }
      } catch (_) {}
    }

    try {
      await logFile!.writeAsString(content, mode: FileMode.append);
      currentLogCount += newLogCount;
    } catch (_) {
      try {
        await logFile!.parent.create(recursive: true);
        await logFile!.writeAsString(content, mode: FileMode.write);
        currentLogCount = newLogCount;
      } catch (_) {}
    }
  }

  Future<void> _rotateBySize() async {
    if (!await logFile!.exists()) return;
    try {
      final content = await logFile!.readAsString();
      final logs = _splitLogEntries(content);
      final keepCount = (logs.length / 2).ceil();
      final kept = logs.skip(logs.length - keepCount).toList();
      final newContent = kept.join('\n');
      await logFile!.writeAsString(newContent);
      currentLogCount = kept.length;
    } catch (e) {
      log(e.toString(), name: 'TalkerPersistentHistory');
    }
  }

  Future<String> read() async => logFile == null ? '' : await logFile!.readAsString();

  // Replaces the file content entirely — used by capacity rotation so that
  // trimmed entries are removed rather than re-appended.
  Future<void> overwriteEntries(List<String> entries) async {
    if (logFile == null) return;
    try {
      await logFile!.writeAsString(entries.isEmpty ? '' : entries.join('\n'));
      currentLogCount = entries.length;
    } catch (_) {}
  }

  Future<void> dispose() async {
    logFile = null;
    currentLogCount = 0;
    currentDate = null;
    baseName = null;
  }
}

/// Configuration class for TalkerPersistentHistory
class TalkerPersistentConfig {
  /// Buffer size for logs. 0 = real-time (write immediately). >0 = batch writes.
  final int bufferSize;

  /// Flush immediately for error and critical logs.
  final bool flushOnError;

  /// Maximum number of log entries to keep in the file.
  final int maxCapacity;

  /// Enable file-based logging.
  final bool enableFileLogging;

  /// Enable Hive database logging.
  final bool enableHiveLogging;

  /// Save logs in daily files named `logName-YYYY-MM-DD.log`.
  final bool saveAllLogs;

  /// How many days to retain daily log files. Only used with [saveAllLogs].
  final int retentionDays;

  /// Maximum log file size in megabytes before rotation (default: 5 MB).
  /// Accepts decimals, e.g. `0.01` for ~10 KB.
  final double maxFileSizeMb;

  /// Include request body in HTTP log entries.
  final bool logRequestBody;

  /// Maximum characters to log for a request body before truncating.
  final int maxRequestBodyLength;

  const TalkerPersistentConfig({
    this.bufferSize = 100,
    this.flushOnError = true,
    this.maxCapacity = 1000,
    this.enableFileLogging = true,
    this.enableHiveLogging = true,
    this.saveAllLogs = false,
    this.retentionDays = 3,
    this.maxFileSizeMb = 5.0,
    this.logRequestBody = false,
    this.maxRequestBodyLength = 5000,
  });

  TalkerPersistentConfig copyWith({
    int? bufferSize,
    bool? flushOnError,
    int? maxCapacity,
    bool? enableFileLogging,
    bool? enableHiveLogging,
    bool? saveAllLogs,
    int? retentionDays,
    double? maxFileSizeMb,
    bool? logRequestBody,
    int? maxRequestBodyLength,
  }) {
    return TalkerPersistentConfig(
      bufferSize: bufferSize ?? this.bufferSize,
      flushOnError: flushOnError ?? this.flushOnError,
      maxCapacity: maxCapacity ?? this.maxCapacity,
      enableFileLogging: enableFileLogging ?? this.enableFileLogging,
      enableHiveLogging: enableHiveLogging ?? this.enableHiveLogging,
      saveAllLogs: saveAllLogs ?? this.saveAllLogs,
      retentionDays: retentionDays ?? this.retentionDays,
      maxFileSizeMb: maxFileSizeMb ?? this.maxFileSizeMb,
      logRequestBody: logRequestBody ?? this.logRequestBody,
      maxRequestBodyLength: maxRequestBodyLength ?? this.maxRequestBodyLength,
    );
  }
}

/// A persistent implementation of [TalkerHistory] that stores logs on disk.
class TalkerPersistentHistory implements TalkerHistory {
  final String logName;
  final String? savePath;
  final TalkerPersistentConfig config;

  final List<String> _writeBuffer = [];
  bool _isInitialized = false;
  bool _isFlushing = false;
  Completer<void>? _flushDone;
  _LogFileManager? _fileManager;

  TalkerPersistentHistory({
    required this.logName,
    this.savePath,
    TalkerPersistentConfig? config,
  }) : config = config ?? const TalkerPersistentConfig();

  static Future<TalkerPersistentHistory> create({
    required String logName,
    String? savePath,
    TalkerPersistentConfig? config,
  }) async {
    final history = TalkerPersistentHistory(logName: logName, savePath: savePath, config: config);
    await history._initialize();
    return history;
  }

  Future<void> _initialize() async {
    if (savePath == null || !config.enableFileLogging || _isInitialized) return;
    try {
      _fileManager = _LogFileManager(
        filePath: path.join(savePath!, '$logName.$_extension'),
        saveAllLogs: config.saveAllLogs,
        retentionDays: config.retentionDays,
        maxFileSize: (config.maxFileSizeMb * 1024 * 1024).round(),
      );
      await _fileManager!.initialize();
      _isInitialized = true;
    } catch (_) {
      _isInitialized = false;
    }
  }

  Future<void> _rotateLogFile() async {
    if (!config.enableFileLogging || config.saveAllLogs || _fileManager == null) return;
    // Fast path: use the in-memory count to avoid reading the file on every flush.
    if (_fileManager!.currentLogCount <= config.maxCapacity) return;
    try {
      final content = await _fileManager!.read();
      final logs = _splitLogEntries(content);
      // Keep the newest half (mirrors _rotateBySize) so the next rotation
      // fires only after another maxCapacity/2 writes, not on every write.
      final keepCount = (logs.length / 2).ceil();
      final kept = logs.skip(logs.length - keepCount).toList();
      await _fileManager!.overwriteEntries(kept);
    } catch (e) {
      log(e.toString(), name: 'TalkerPersistentHistory');
    }
  }

  /// Flushes the write buffer to disk.
  /// Guard flag prevents concurrent flushes that would cause duplicate entries.
  /// Items added while a flush is in progress are picked up by the inner while-loop.
  Future<void> _flushBuffer() async {
    if (_isFlushing || _writeBuffer.isEmpty || !_isInitialized || !config.enableFileLogging) return;
    _isFlushing = true;
    _flushDone = Completer<void>();
    try {
      while (_writeBuffer.isNotEmpty) {
        final batch = List<String>.from(_writeBuffer);
        _writeBuffer.clear();
        await _fileManager?.write(batch);
      }
    } catch (_) {
    } finally {
      _isFlushing = false;
      _flushDone?.complete();
      _flushDone = null;
    }
  }

  bool _shouldFlushImmediately(TalkerData data) {
    if (!config.flushOnError) return false;
    return data.logLevel == LogLevel.error || data.logLevel == LogLevel.critical;
  }

  bool _isHttpLog(TalkerData data) {
    if (data is DioRequestLog || data is DioResponseLog || data is DioErrorLog) return true;
    final title = data.title?.toLowerCase() ?? '';
    return ['httperror', 'httprequest', 'httpresponse', 'http-request', 'http-response', 'http-error'].contains(title);
  }

  String _safeBodyString(dynamic body) {
    if (body == null) return '';
    if (body is List<int>) return '[binary]';
    try {
      final s = body.toString();
      return s.length > config.maxRequestBodyLength ? '${s.substring(0, config.maxRequestBodyLength)}... [truncated]' : s;
    } catch (_) {
      return '';
    }
  }

  String _formatDioLog(TalkerData data) {
    final timestamp = data.time.toIso8601String();
    final level = data.logLevel?.name.toUpperCase() ?? 'UNKNOWN';

    if (data is DioRequestLog) {
      final method = data.requestOptions.method;
      final url = data.requestOptions.uri.toString();
      var entry = '$timestamp [$level] [REQUEST] $method $url';
      if (config.logRequestBody) {
        final body = _safeBodyString(data.requestOptions.data);
        if (body.isNotEmpty) entry += ' [REQUEST BODY] $body';
      }
      return entry;
    }

    if (data is DioResponseLog) {
      final status = data.response.statusCode;
      final method = data.response.requestOptions.method;
      final url = data.response.requestOptions.uri.toString();
      final responseData = data.response.data;
      final body = responseData != null && responseData is! List<int> ? _safeBodyString(responseData) : '';
      var entry = '$timestamp [$level] [RESPONSE] $status $method $url';
      if (body.isNotEmpty) entry += '\n$timestamp [$level] [RESPONSE BODY] $body';
      return entry;
    }

    if (data is DioErrorLog) {
      final method = data.dioException.requestOptions.method;
      final url = data.dioException.requestOptions.uri.toString();
      final status = data.dioException.response?.statusCode;
      final errorMsg = data.dioException.message ?? data.dioException.type.name;
      return '$timestamp [$level] [HTTP ERROR]${status != null ? ' $status' : ''} $method $url - $errorMsg';
    }

    // Fallback for non-Dio HTTP logs identified by title
    final title = data.title?.toUpperCase() ?? 'HTTP';
    final msg = (data.message ?? '').replaceAll(RegExp(r'[\r\n]+'), ' ');
    final truncated = msg.length > 500 ? '${msg.substring(0, 500)}...' : msg;
    return '$timestamp [$level] [$title] $truncated';
  }

  String formatLogSimple(TalkerData data) {
    final timestamp = data.time.toIso8601String();
    final level = data.logLevel?.name.toUpperCase() ?? 'UNKNOWN';
    var msg = (data.message ?? '').replaceAll(RegExp(r'[\r\n]+'), ' ');
    if (msg.length > 800) msg = '${msg.substring(0, 800)}...';

    if (data.logLevel == LogLevel.error || data.logLevel == LogLevel.critical) {
      final stack = data.stackTrace?.toString().replaceAll(RegExp(r'[\r\n]+'), ' ') ?? '';
      return '$timestamp [$level] $msg${stack.isNotEmpty ? ' [STACK] $stack' : ''}';
    }
    return '$timestamp [$level] $msg';
  }

  @override
  void write(TalkerData data) {
    if (config.enableHiveLogging) {
      TalkerPersistent.instance.write(data: data, logName: logName, maxCapacity: config.maxCapacity);
    }

    if (!_isInitialized || !config.enableFileLogging) return;

    try {
      final entry = _isHttpLog(data) ? _formatDioLog(data) : formatLogSimple(data);
      _writeBuffer.add(entry);

      final shouldFlush = config.bufferSize == 0 || _shouldFlushImmediately(data) || _writeBuffer.length >= config.bufferSize;

      if (shouldFlush) {
        _flushBuffer();
        if (!config.saveAllLogs) _rotateLogFile();
      }
    } catch (_) {
      if (_writeBuffer.length > 1000) _writeBuffer.clear();
    }
  }

  @override
  void clean() {
    if (config.enableHiveLogging) TalkerPersistent.instance.clean(logName: logName);
  }

  @override
  List<TalkerData> get history {
    if (!config.enableHiveLogging) return [];
    return List.unmodifiable(TalkerPersistent.instance.getLogs(logName: logName));
  }

  Future<void> dispose() async {
    if (_isInitialized && config.enableFileLogging) {
      // Wait for any in-progress flush so we don't nullify _fileManager under it
      if (_isFlushing) await _flushDone?.future;
      // Flush anything that accumulated while we were waiting
      await _flushBuffer();
      await _fileManager?.dispose();
      _fileManager = null;
      _isInitialized = false;
    }
    if (config.enableHiveLogging) {
      try {
        await Hive.close();
      } catch (e) {
        log(e.toString(), name: 'TalkerPersistentHistory');
      }
    }
  }
}
