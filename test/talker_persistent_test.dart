import 'dart:io';

import 'package:dio/dio.dart';
import 'package:hive_ce/hive.dart';
import 'package:talker/talker.dart';
import 'package:talker_dio_logger/dio_logs.dart';
import 'package:talker_dio_logger/talker_dio_logger.dart';
import 'package:talker_persistent/talker_persistent.dart';
import 'package:test/test.dart';

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

const _settings = TalkerDioLoggerSettings();

TalkerData _infoLog(String msg) => TalkerLog(msg, logLevel: LogLevel.info);
TalkerData _errorLog(String msg, {StackTrace? stackTrace}) =>
    TalkerLog(msg, logLevel: LogLevel.error, stackTrace: stackTrace);
TalkerData _criticalLog(String msg) => TalkerLog(msg, logLevel: LogLevel.critical);

DioRequestLog _requestLog(String url, {String method = 'GET', dynamic data}) {
  final opts = RequestOptions(path: url, method: method, data: data);
  return DioRequestLog(url, requestOptions: opts, settings: _settings);
}

DioResponseLog _responseLog(String url,
    {String method = 'GET', int statusCode = 200, dynamic responseData}) {
  final opts = RequestOptions(path: url, method: method);
  final response = Response<dynamic>(
    requestOptions: opts,
    statusCode: statusCode,
    data: responseData,
  );
  return DioResponseLog(url, response: response, settings: _settings);
}

DioErrorLog _errorDioLog(String url,
    {String method = 'GET', int? statusCode, String? message}) {
  final opts = RequestOptions(path: url, method: method);
  final exception = DioException(
    requestOptions: opts,
    message: message ?? 'Connection failed',
    type: DioExceptionType.connectionTimeout,
    response: statusCode != null
        ? Response(requestOptions: opts, statusCode: statusCode)
        : null,
  );
  return DioErrorLog('HTTP Error', dioException: exception, settings: _settings);
}

Future<TalkerPersistentHistory> _makeHistory(
  Directory dir, {
  int bufferSize = 0,
  bool logRequestBody = false,
  int retentionDays = 3,
  bool saveAllLogs = false,
  double maxFileSizeMb = 5.0,
  String logName = 'test',
}) =>
    TalkerPersistentHistory.create(
      logName: logName,
      savePath: dir.path,
      config: TalkerPersistentConfig(
        bufferSize: bufferSize,
        enableHiveLogging: false,
        logRequestBody: logRequestBody,
        retentionDays: retentionDays,
        saveAllLogs: saveAllLogs,
        maxFileSizeMb: maxFileSizeMb,
      ),
    );

Future<String> _readLog(Directory dir, String logName) =>
    File('${dir.path}/$logName.log').readAsString();

// ────────────────────────────────────────────────────────────────────────────
// TalkerPersistentConfig
// ────────────────────────────────────────────────────────────────────────────

void main() {
  group('TalkerPersistentConfig', () {
    test('default values', () {
      const cfg = TalkerPersistentConfig();
      expect(cfg.bufferSize, 100);
      expect(cfg.flushOnError, isTrue);
      expect(cfg.maxCapacity, 1000);
      expect(cfg.enableFileLogging, isTrue);
      expect(cfg.enableHiveLogging, isTrue);
      expect(cfg.saveAllLogs, isFalse);
      expect(cfg.retentionDays, 3);
      expect(cfg.maxFileSizeMb, 5.0);
      expect(cfg.logRequestBody, isFalse);
      expect(cfg.maxRequestBodyLength, 5000);
    });

    test('copyWith updates only specified fields', () {
      const base = TalkerPersistentConfig();
      final updated = base.copyWith(retentionDays: 14, bufferSize: 0, logRequestBody: true);

      expect(updated.retentionDays, 14);
      expect(updated.bufferSize, 0);
      expect(updated.logRequestBody, isTrue);
      // Unchanged fields
      expect(updated.flushOnError, base.flushOnError);
      expect(updated.maxCapacity, base.maxCapacity);
      expect(updated.enableFileLogging, base.enableFileLogging);
      expect(updated.enableHiveLogging, base.enableHiveLogging);
      expect(updated.saveAllLogs, base.saveAllLogs);
      expect(updated.maxFileSizeMb, base.maxFileSizeMb);
      expect(updated.maxRequestBodyLength, base.maxRequestBodyLength);
    });

    test('copyWith with no args produces identical values', () {
      const cfg = TalkerPersistentConfig(
        bufferSize: 50,
        retentionDays: 7,
        maxFileSizeMb: 10.0,
        saveAllLogs: true,
      );
      final copy = cfg.copyWith();
      expect(copy.bufferSize, 50);
      expect(copy.retentionDays, 7);
      expect(copy.maxFileSizeMb, 10.0);
      expect(copy.saveAllLogs, isTrue);
    });

    test('retentionDays can be set to any positive int', () {
      for (final days in [1, 3, 7, 14, 30, 365]) {
        final cfg = TalkerPersistentConfig(retentionDays: days);
        expect(cfg.retentionDays, days);
      }
    });

    test('maxFileSizeMb accepts decimal (KB-range) values', () {
      // 0.01 MB = 10240 bytes; 0.001 MB = 1048 bytes (~1 KB)
      for (final mb in [0.001, 0.01, 0.1, 0.5, 1.0, 5.0, 50.0]) {
        final cfg = TalkerPersistentConfig(maxFileSizeMb: mb);
        expect(cfg.maxFileSizeMb, mb);
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // formatLogSimple
  // ──────────────────────────────────────────────────────────────────────────

  group('TalkerPersistentHistory.formatLogSimple', () {
    late TalkerPersistentHistory h;

    setUp(() {
      h = TalkerPersistentHistory(
        logName: 'fmt',
        config: const TalkerPersistentConfig(
          enableHiveLogging: false,
          enableFileLogging: false,
        ),
      );
    });

    test('includes timestamp, level and message', () {
      final result = h.formatLogSimple(_infoLog('hello world'));
      expect(result, matches(RegExp(r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')));
      expect(result, contains('[INFO]'));
      expect(result, contains('hello world'));
    });

    test('truncates messages longer than 800 characters', () {
      final longMsg = 'A' * 900;
      final result = h.formatLogSimple(_infoLog(longMsg));
      expect(result, contains('...'));
      expect(result.contains('A' * 801), isFalse);
    });

    test('replaces newlines with spaces', () {
      final result = h.formatLogSimple(_infoLog('line1\nline2\r\nline3'));
      expect(result, isNot(contains('\n')));
      expect(result, isNot(contains('\r')));
      // [\r\n]+ collapses each newline sequence into a single space
      expect(result, contains('line1 line2 line3'));
    });

    test('error level includes [STACK] when stack trace present', () {
      final stack = StackTrace.fromString('#0 main (test.dart:1:1)');
      final result = h.formatLogSimple(_errorLog('oops', stackTrace: stack));
      expect(result, contains('[ERROR]'));
      expect(result, contains('[STACK]'));
      expect(result, contains('test.dart:1:1'));
    });

    test('critical level includes [STACK] when stack trace present', () {
      final stack = StackTrace.fromString('#0 main (test.dart:2:1)');
      final log = TalkerLog('crash',
          logLevel: LogLevel.critical, stackTrace: stack);
      final result = h.formatLogSimple(log);
      expect(result, contains('[CRITICAL]'));
      expect(result, contains('[STACK]'));
    });

    test('info level without stack trace does not include [STACK]', () {
      final result = h.formatLogSimple(_infoLog('no stack'));
      expect(result, isNot(contains('[STACK]')));
    });

    test('warning level works correctly', () {
      final result =
          h.formatLogSimple(TalkerLog('warn msg', logLevel: LogLevel.warning));
      expect(result, contains('[WARNING]'));
      expect(result, contains('warn msg'));
    });

    test('debug level works correctly', () {
      final result =
          h.formatLogSimple(TalkerLog('dbg msg', logLevel: LogLevel.debug));
      expect(result, contains('[DEBUG]'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // File logging — writes, buffer, no-duplicate guarantee
  // ──────────────────────────────────────────────────────────────────────────

  group('TalkerPersistentHistory — file logging', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tp_file_');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('writes a single log to file', () async {
      final h = await _makeHistory(dir);
      h.write(_infoLog('hello file'));
      await h.dispose();

      final content = await _readLog(dir, 'test');
      expect(content, contains('hello file'));
      expect(content, contains('[INFO]'));
    });

    test('all logs appear in file', () async {
      final h = await _makeHistory(dir);
      for (var i = 0; i < 5; i++) {
        h.write(_infoLog('entry-$i'));
      }
      await h.dispose();

      final content = await _readLog(dir, 'test');
      for (var i = 0; i < 5; i++) {
        expect(content, contains('entry-$i'), reason: 'entry-$i missing');
      }
    });

    test('dispose flushes buffered logs that have not reached buffer size', () async {
      final h = await _makeHistory(dir, bufferSize: 100);
      h.write(_infoLog('buffered-only'));
      await h.dispose();

      final content = await _readLog(dir, 'test');
      expect(content, contains('buffered-only'));
    });

    test('buffer flushes when it reaches bufferSize', () async {
      final h = await _makeHistory(dir, bufferSize: 5);
      for (var i = 0; i < 5; i++) {
        h.write(_infoLog('buf-$i'));
      }
      await Future.delayed(const Duration(milliseconds: 100));

      final logFile = File('${dir.path}/test.log');
      expect(await logFile.exists(), isTrue);
      final content = await logFile.readAsString();
      expect(content, contains('buf-0'));
      await h.dispose();
    });

    test('error log triggers immediate flush regardless of buffer size', () async {
      final h = await _makeHistory(dir, bufferSize: 100);
      h.write(_infoLog('before error'));
      h.write(_errorLog('urgent error'));
      await Future.delayed(const Duration(milliseconds: 100));

      final content = await _readLog(dir, 'test');
      expect(content, contains('urgent error'));
      await h.dispose();
    });

    test('critical log triggers immediate flush', () async {
      final h = await _makeHistory(dir, bufferSize: 100);
      h.write(_criticalLog('system down'));
      await Future.delayed(const Duration(milliseconds: 100));

      final content = await _readLog(dir, 'test');
      expect(content, contains('system down'));
      await h.dispose();
    });

    // ── No-duplicate guarantee (core bug fix) ──────────────────────────────

    test('30 rapid writes in real-time mode produce no duplicates', () async {
      final h = await _makeHistory(dir, bufferSize: 0);

      // All writes are synchronous — triggers concurrent flushes in the old code
      for (var i = 0; i < 30; i++) {
        h.write(_infoLog('message-${i.toString().padLeft(3, '0')}-end'));
      }
      await h.dispose();

      final content = await _readLog(dir, 'test');
      for (var i = 0; i < 30; i++) {
        final key = 'message-${i.toString().padLeft(3, '0')}-end';
        final count = key.allMatches(content).length;
        expect(count, 1, reason: '"$key" should appear exactly once, got $count');
      }
    });

    test('50 rapid writes with bufferSize=10 produce no duplicates', () async {
      final h = await _makeHistory(dir, bufferSize: 10);

      for (var i = 0; i < 50; i++) {
        h.write(_infoLog('item-${i.toString().padLeft(3, '0')}-end'));
      }
      await h.dispose();

      final content = await _readLog(dir, 'test');
      for (var i = 0; i < 50; i++) {
        final key = 'item-${i.toString().padLeft(3, '0')}-end';
        final count = key.allMatches(content).length;
        expect(count, 1, reason: '"$key" duplicated: $count times');
      }
    });

    test('file is not created when enableFileLogging is false', () async {
      final h = await TalkerPersistentHistory.create(
        logName: 'nolog',
        savePath: dir.path,
        config: const TalkerPersistentConfig(
          enableFileLogging: false,
          enableHiveLogging: false,
        ),
      );
      h.write(_infoLog('ignored'));
      await h.dispose();

      expect(await File('${dir.path}/nolog.log').exists(), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // HTTP log formatting — DioRequestLog / DioResponseLog / DioErrorLog
  // ──────────────────────────────────────────────────────────────────────────

  group('TalkerPersistentHistory — HTTP log formatting', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tp_http_');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    Future<String> write1AndRead(TalkerData log,
        {bool logRequestBody = false}) async {
      final h = await _makeHistory(dir,
          bufferSize: 0,
          logRequestBody: logRequestBody,
          logName: 'http');
      h.write(log);
      await h.dispose();
      return _readLog(dir, 'http');
    }

    // ── DioRequestLog ──────────────────────────────────────────────────────

    test('DioRequestLog: contains [REQUEST], method and URL', () async {
      final content = await write1AndRead(
          _requestLog('https://api.example.com/users', method: 'POST'));

      expect(content, contains('[REQUEST]'));
      expect(content, contains('POST'));
      expect(content, contains('/users'));
    });

    test('DioRequestLog: does NOT contain box-drawing chars from default formatter',
        () async {
      final content = await write1AndRead(_requestLog('/api/data'));
      expect(content, isNot(contains('│')));
      expect(content, isNot(contains('└')));
      expect(content, isNot(contains('┐')));
    });

    test('DioRequestLog: logRequestBody=false omits body', () async {
      final content = await write1AndRead(
          _requestLog('/api/items', method: 'POST', data: {'qty': 5}),
          logRequestBody: false);

      expect(content, isNot(contains('[REQUEST BODY]')));
    });

    test('DioRequestLog: logRequestBody=true includes body', () async {
      final content = await write1AndRead(
          _requestLog('/api/items', method: 'POST',
              data: {'name': 'widget', 'qty': 5}),
          logRequestBody: true);

      expect(content, contains('[REQUEST BODY]'));
      expect(content, contains('widget'));
    });

    test('DioRequestLog: binary data produces [binary] placeholder', () async {
      final content = await write1AndRead(
          _requestLog('/upload', method: 'POST',
              data: [0, 1, 2, 3, 4]),  // List<int>
          logRequestBody: true);

      // List<int> should show [binary], not raw bytes
      expect(content, contains('[binary]'));
    });

    // ── DioResponseLog ─────────────────────────────────────────────────────

    test('DioResponseLog: contains [RESPONSE], status, method, URL', () async {
      final content = await write1AndRead(
          _responseLog('https://api.example.com/users',
              method: 'GET', statusCode: 200));

      expect(content, contains('[RESPONSE]'));
      expect(content, contains('200'));
      expect(content, contains('GET'));
      expect(content, contains('/users'));
    });

    test('DioResponseLog: 4xx status code is included', () async {
      final content =
          await write1AndRead(_responseLog('/resource', statusCode: 404));
      expect(content, contains('404'));
    });

    test('DioResponseLog: body is included as [RESPONSE BODY] when present',
        () async {
      final content = await write1AndRead(
          _responseLog('/data', responseData: {'id': 42, 'name': 'Bob'}));

      expect(content, contains('[RESPONSE BODY]'));
      expect(content, contains('Bob'));
    });

    test('DioResponseLog: null body does not produce [RESPONSE BODY]', () async {
      final content =
          await write1AndRead(_responseLog('/empty', responseData: null));
      expect(content, isNot(contains('[RESPONSE BODY]')));
    });

    test('DioResponseLog: List<int> body is skipped (binary)', () async {
      final content = await write1AndRead(
          _responseLog('/binary', responseData: [0, 1, 2, 3]));
      expect(content, isNot(contains('[RESPONSE BODY]')));
    });

    // ── DioErrorLog ────────────────────────────────────────────────────────

    test('DioErrorLog: contains [HTTP ERROR], method, URL, error message',
        () async {
      final content = await write1AndRead(
          _errorDioLog('https://api.example.com/orders',
              method: 'DELETE', message: 'Connection timeout'));

      expect(content, contains('[HTTP ERROR]'));
      expect(content, contains('DELETE'));
      expect(content, contains('Connection timeout'));
    });

    test('DioErrorLog: status code included when response is present', () async {
      final content = await write1AndRead(
          _errorDioLog('/resource', statusCode: 403));

      expect(content, contains('[HTTP ERROR]'));
      expect(content, contains('403'));
    });

    test('DioErrorLog: no status when response is absent', () async {
      final log = _errorDioLog('/timeout', statusCode: null);
      final content = await write1AndRead(log);
      expect(content, contains('[HTTP ERROR]'));
    });

    // ── No duplication when REQUEST + RESPONSE both logged ─────────────────

    test('Request + Response produce exactly one [REQUEST] and one [RESPONSE]',
        () async {
      final h = await _makeHistory(dir, bufferSize: 0, logName: 'nodupe');
      h.write(_requestLog('https://api.example.com/items', method: 'GET'));
      h.write(_responseLog('https://api.example.com/items',
          method: 'GET', statusCode: 200, responseData: 'ok'));
      await h.dispose();

      final content = await _readLog(dir, 'nodupe');

      final reqCount = '[REQUEST]'.allMatches(content).length;
      final resCount = '[RESPONSE]'.allMatches(content).length;

      expect(reqCount, 1,
          reason: '[REQUEST] should appear once, got $reqCount\n$content');
      expect(resCount, 1,
          reason: '[RESPONSE] should appear once, got $resCount\n$content');
    });

    test('20 request-response pairs produce no duplicates', () async {
      final h = await _makeHistory(dir, bufferSize: 0, logName: 'pairs');

      for (var i = 0; i < 20; i++) {
        final url = '/endpoint/$i';
        h.write(_requestLog(url));
        h.write(_responseLog(url, statusCode: 200));
      }
      await h.dispose();

      final content = await _readLog(dir, 'pairs');
      final reqCount = '[REQUEST]'.allMatches(content).length;
      final resCount = RegExp(r'\[RESPONSE\]').allMatches(content).length;

      expect(reqCount, 20,
          reason: 'Expected 20 [REQUEST], got $reqCount');
      expect(resCount, 20,
          reason: 'Expected 20 [RESPONSE], got $resCount');
    });

    // ── Body truncation ────────────────────────────────────────────────────

    test('request body is truncated when it exceeds maxRequestBodyLength',
        () async {
      final bigBody = {'data': 'X' * 6000};
      final h = await TalkerPersistentHistory.create(
        logName: 'trunc',
        savePath: dir.path,
        config: const TalkerPersistentConfig(
          bufferSize: 0,
          enableHiveLogging: false,
          logRequestBody: true,
          maxRequestBodyLength: 100,
        ),
      );
      h.write(_requestLog('/big', method: 'POST', data: bigBody));
      await h.dispose();

      final content = await _readLog(dir, 'trunc');
      expect(content, contains('[truncated]'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Log file retention (saveAllLogs + retentionDays)
  // ──────────────────────────────────────────────────────────────────────────

  group('TalkerPersistentHistory — retention', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tp_retention_');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    String dateStr(DateTime dt) =>
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

    test('old log files beyond retentionDays are deleted on initialize', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 10));
      final oldFile = File('${dir.path}/test-${dateStr(oldDate)}.log');
      await oldFile.writeAsString('old log content');

      final h = await _makeHistory(dir,
          saveAllLogs: true, retentionDays: 3);
      await h.dispose();

      expect(await oldFile.exists(), isFalse,
          reason: 'File older than retentionDays should be deleted');
    });

    test('log files within retentionDays are preserved', () async {
      final recentDate = DateTime.now().subtract(const Duration(days: 1));
      final recentFile = File('${dir.path}/test-${dateStr(recentDate)}.log');
      await recentFile.writeAsString('recent log');

      final h = await _makeHistory(dir,
          saveAllLogs: true, retentionDays: 3);
      await h.dispose();

      expect(await recentFile.exists(), isTrue,
          reason: 'File within retentionDays should be preserved');
    });

    test('file exactly at retention boundary is deleted (> not >=)', () async {
      final borderDate =
          DateTime.now().subtract(const Duration(days: 4));
      final borderFile = File('${dir.path}/test-${dateStr(borderDate)}.log');
      await borderFile.writeAsString('border log');

      final h = await _makeHistory(dir,
          saveAllLogs: true, retentionDays: 3);
      await h.dispose();

      expect(await borderFile.exists(), isFalse);
    });

    test('retentionDays=7 preserves files from 6 days ago', () async {
      final recentDate = DateTime.now().subtract(const Duration(days: 6));
      final recentFile = File('${dir.path}/test-${dateStr(recentDate)}.log');
      await recentFile.writeAsString('6 day old log');

      final h = await _makeHistory(dir,
          saveAllLogs: true, retentionDays: 7);
      await h.dispose();

      expect(await recentFile.exists(), isTrue);
    });

    test('retentionDays=7 deletes files from 8 days ago', () async {
      final oldDate = DateTime.now().subtract(const Duration(days: 8));
      final oldFile = File('${dir.path}/test-${dateStr(oldDate)}.log');
      await oldFile.writeAsString('old log');

      final h = await _makeHistory(dir,
          saveAllLogs: true, retentionDays: 7);
      await h.dispose();

      expect(await oldFile.exists(), isFalse);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // File size rotation
  // ──────────────────────────────────────────────────────────────────────────

  group('TalkerPersistentHistory — size rotation', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tp_rotate_');
    });

    tearDown(() async {
      await dir.delete(recursive: true);
    });

    test('size rotation removes old entries when limit is exceeded', () async {
      // Pre-populate with exactly maxCapacity (1000) entries so _rotateLogFile
      // returns early (logCount <= maxCapacity), avoiding a race with _flushBuffer.
      // Each entry is ~1060 bytes so 1000 entries ≈ 1.06 MB > the 1 MB limit.
      final logFile = File('${dir.path}/test.log');
      final pad = 'X' * 1010; // 49 + 1010 = ~1059 bytes/entry × 1000 ≈ 1.06 MB
      final lines = List.generate(
        1000,
        (i) =>
            '2024-01-01T00:00:00.000000 [INFO] old-entry-${i.toString().padLeft(4, '0')} $pad',
      ).join('\n');
      await logFile.writeAsString('$lines\n');

      // Initialize history — reads existing file and registers currentLogCount.
      // maxCapacity defaults to 1000, so _rotateLogFile returns early (1000 <= 1000)
      // and only the size-based rotation (_rotateBySize) runs.
      final h = await _makeHistory(dir, bufferSize: 0, maxFileSizeMb: 1.0);

      // One new write: file size + entry > 1 MB → _rotateBySize fires, keeps newest half
      h.write(_infoLog('new-entry-after-rotation'));
      await h.dispose();

      final content = await _readLog(dir, 'test');
      expect(content, contains('new-entry-after-rotation'),
          reason: 'New entry must survive rotation');
      expect(content, isNot(contains('old-entry-0000')),
          reason: 'Oldest entries should have been rotated out');
      expect(content, isNot(contains('old-entry-0001')),
          reason: 'entry-0001 should have been rotated out');
    });

    test('KB-range threshold (0.01 MB ≈ 10 KB) triggers rotation', () async {
      // 0.01 MB = 10240 bytes. Pre-populate with ~12 KB of valid entries.
      final logFile = File('${dir.path}/kb.log');
      final pad = 'X' * 100; // ~150 bytes per entry × 80 entries ≈ 12 KB
      final lines = List.generate(
        80,
        (i) =>
            '2024-01-01T00:00:00.000000 [INFO] kb-old-${i.toString().padLeft(3, '0')} $pad',
      ).join('\n');
      await logFile.writeAsString('$lines\n');

      final h = await _makeHistory(dir,
          bufferSize: 0, maxFileSizeMb: 0.01, logName: 'kb');

      h.write(_infoLog('kb-new-entry'));
      await h.dispose();

      final content = await _readLog(dir, 'kb');
      expect(content, contains('kb-new-entry'),
          reason: 'New entry must survive rotation');
      expect(content, isNot(contains('kb-old-000')),
          reason: 'Oldest KB entries should be rotated out');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // TalkerPersistent — Hive service
  // ──────────────────────────────────────────────────────────────────────────

  group('TalkerPersistent (Hive service)', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('tp_hive_');
      await TalkerPersistent.instance.initialize(
        path: dir.path,
        logNames: {'logs', 'cap'},
      );
    });

    tearDownAll(() async {
      await TalkerPersistent.instance.dispose();
      try {
        await Hive.close();
      } catch (_) {}
      await dir.delete(recursive: true);
    });

    setUp(() {
      TalkerPersistent.instance.clean(logName: 'logs');
      TalkerPersistent.instance.clean(logName: 'cap');
    });

    test('write then getLogs returns the entry', () {
      TalkerPersistent.instance.write(
          data: TalkerLog('hive-entry'), logName: 'logs', maxCapacity: 100);

      final logs = TalkerPersistent.instance.getLogs(logName: 'logs');
      expect(logs.length, 1);
      expect(logs.first.message, contains('hive-entry'));
    });

    test('multiple writes are all retrievable', () {
      for (var i = 0; i < 5; i++) {
        TalkerPersistent.instance.write(
            data: TalkerLog('entry-$i'), logName: 'logs', maxCapacity: 100);
      }
      final logs = TalkerPersistent.instance.getLogs(logName: 'logs');
      expect(logs.length, 5);
    });

    test('clean removes all entries for the logName', () {
      TalkerPersistent.instance.write(
          data: TalkerLog('to be cleaned'), logName: 'logs', maxCapacity: 100);
      TalkerPersistent.instance.clean(logName: 'logs');

      final logs = TalkerPersistent.instance.getLogs(logName: 'logs');
      expect(logs, isEmpty);
    });

    test('clean on one logName does not affect another', () {
      TalkerPersistent.instance.write(
          data: TalkerLog('keep-me'), logName: 'logs', maxCapacity: 100);
      TalkerPersistent.instance.write(
          data: TalkerLog('delete-me'), logName: 'cap', maxCapacity: 100);

      TalkerPersistent.instance.clean(logName: 'cap');

      expect(TalkerPersistent.instance.getLogs(logName: 'logs').length, 1);
      expect(TalkerPersistent.instance.getLogs(logName: 'cap'), isEmpty);
    });

    test('maxCapacity evicts the oldest entry when exceeded', () {
      for (var i = 0; i < 5; i++) {
        TalkerPersistent.instance
            .write(data: TalkerLog('msg-$i'), logName: 'cap', maxCapacity: 3);
      }

      final logs = TalkerPersistent.instance.getLogs(logName: 'cap');
      expect(logs.length, 3);
      final messages = logs.map((e) => e.message ?? '').toList();
      expect(messages, isNot(contains('msg-0')));
      expect(messages, isNot(contains('msg-1')));
      expect(messages, contains('msg-2'));
      expect(messages, contains('msg-3'));
      expect(messages, contains('msg-4'));
    });

    test('getLogs for unknown logName returns empty list', () {
      final logs =
          TalkerPersistent.instance.getLogs(logName: 'nonexistent_xyz');
      expect(logs, isEmpty);
    });

    test('history getter on TalkerPersistentHistory returns Hive data', () async {
      final h = await TalkerPersistentHistory.create(
        logName: 'logs',
        config: const TalkerPersistentConfig(
          enableFileLogging: false,
          enableHiveLogging: true,
        ),
      );
      h.write(TalkerLog('hive-history'));

      expect(h.history.length, greaterThanOrEqualTo(1));
      expect(
          h.history.any((e) => e.message?.contains('hive-history') ?? false),
          isTrue);
    });
  });
}
