# talker_persistent

An extension for the [talker](https://pub.dev/packages/talker) package that persists logs to disk files and a [Hive CE](https://pub.dev/packages/hive_ce) database.

## Features

- Write logs to rotating text files with configurable size limit
- Persist logs to Hive for in-app retrieval (`history` getter)
- Configurable write buffer — real-time (`bufferSize: 0`) or batched
- Immediate flush for `error` and `critical` log levels
- Clean single-line formatting for Dio HTTP logs (`[REQUEST]`, `[RESPONSE]`, `[HTTP ERROR]`)
- Optional request body logging with configurable max length
- Daily log files with automatic retention cleanup (`saveAllLogs`)
- Works with Flutter and pure Dart

## Installation

```yaml
dependencies:
  talker_persistent: ^3.0.0
```

## Quick start

```dart
import 'package:talker/talker.dart';
import 'package:talker_persistent/talker_persistent.dart';

void main() async {
  // Required only when enableHiveLogging is true (the default)
  await TalkerPersistent.instance.initialize(
    path: 'path/to/hive/directory',
    logNames: {'app'},
  );

  final history = await TalkerPersistentHistory.create(
    logName: 'app',
    savePath: 'logs',
  );

  final talker = Talker(history: history);

  talker.info('Application started');
  talker.error('Something went wrong');

  await history.dispose();
}
```

## Configuration

Pass a `TalkerPersistentConfig` to `TalkerPersistentHistory.create`:

```dart
final history = await TalkerPersistentHistory.create(
  logName: 'app',
  savePath: 'logs',
  config: TalkerPersistentConfig(
    bufferSize: 0,           // real-time (0) or batched (> 0)
    flushOnError: true,      // flush immediately on error/critical
    maxCapacity: 1000,       // max entries kept in Hive
    enableFileLogging: true,
    enableHiveLogging: true,
    maxFileSizeMb: 5,        // rotate file when it exceeds this size
    logRequestBody: false,   // include HTTP request body in file logs
    maxRequestBodyLength: 5000,
  ),
);
```

### All options

| Option | Type | Default | Description |
|---|---|---|---|
| `bufferSize` | `int` | `100` | Entries to accumulate before flushing. `0` = write every entry immediately. |
| `flushOnError` | `bool` | `true` | Flush the buffer immediately when an `error` or `critical` entry is written. |
| `maxCapacity` | `int` | `1000` | Maximum entries kept in the Hive database. Oldest entries are evicted first. |
| `enableFileLogging` | `bool` | `true` | Write logs to a text file. |
| `enableHiveLogging` | `bool` | `true` | Persist logs in Hive (required for `history` getter). |
| `saveAllLogs` | `bool` | `false` | Write to daily files named `logName-YYYY-MM-DD.log` instead of a single file. |
| `retentionDays` | `int` | `3` | Number of days to keep daily log files (used with `saveAllLogs: true`). |
| `maxFileSizeMb` | `double` | `5.0` | Maximum file size in MB. Accepts decimals (e.g. `0.01` ≈ 10 KB). When exceeded, the oldest half of entries is removed. |
| `logRequestBody` | `bool` | `false` | Include the HTTP request body in file log entries. |
| `maxRequestBodyLength` | `int` | `5000` | Truncate request/response bodies beyond this many characters. |

## File log format

Each entry is a single line starting with an ISO-8601 timestamp:

```
2024-06-01T12:34:56.789000 [INFO] User logged in
2024-06-01T12:34:57.001000 [ERROR] DB connection failed [STACK] #0 main (main.dart:42)
2024-06-01T12:34:58.123000 [INFO] [REQUEST] POST https://api.example.com/orders
2024-06-01T12:34:58.456000 [INFO] [RESPONSE] 201 POST https://api.example.com/orders
2024-06-01T12:34:58.456000 [INFO] [RESPONSE BODY] {"id":99,"status":"created"}
```

## Daily log files

When `saveAllLogs: true`, a new file is created each day and old files are automatically deleted after `retentionDays`:

```dart
final history = await TalkerPersistentHistory.create(
  logName: 'app',
  savePath: 'logs',
  config: TalkerPersistentConfig(
    saveAllLogs: true,
    retentionDays: 7,
  ),
);
// Creates: logs/app-2024-06-01.log, logs/app-2024-06-02.log, …
```

## Dio HTTP logging

Pair with [talker_dio_logger](https://pub.dev/packages/talker_dio_logger) to automatically capture HTTP traffic:

```dart
final talker = Talker(history: history);

dio.interceptors.add(
  TalkerDioLogger(
    talker: talker,
    settings: TalkerDioLoggerSettings(
      printRequestData: true,
    ),
  ),
);
```

Log entries are formatted without box-drawing characters, making them easy to parse or grep:

```
2024-06-01T12:00:00.000 [INFO] [REQUEST] GET https://api.example.com/users
2024-06-01T12:00:00.150 [INFO] [RESPONSE] 200 GET https://api.example.com/users
2024-06-01T12:00:05.000 [ERROR] [HTTP ERROR] 503 GET https://api.example.com/users - Service Unavailable
```

## Reading history

The `history` getter returns entries from Hive (requires `enableHiveLogging: true`):

```dart
final logs = history.history; // List<TalkerData>
for (final entry in logs) {
  print('${entry.time} ${entry.logLevel} ${entry.message}');
}
```

## Cleanup

Always call `dispose` before your app exits to flush any buffered entries:

```dart
await history.dispose();
```

## Migration from 2.x

```dart
// Before
TalkerPersistentConfig(
  logRetentionPeriod: LogRetentionPeriod.week,
  maxFileSize: 50 * 1024 * 1024,
)

// After
TalkerPersistentConfig(
  retentionDays: 7,
  maxFileSizeMb: 50,
)
```

## License

MIT
