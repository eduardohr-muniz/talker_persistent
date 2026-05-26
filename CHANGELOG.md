# Changelog

## 3.0.0

### Breaking changes
- Removed `LogRetentionPeriod` enum. Pass days directly as `int`:
  ```dart
  // before
  logRetentionPeriod: LogRetentionPeriod.week
  // after
  retentionDays: 7
  ```
- Renamed `maxFileSize` (bytes) → `maxFileSizeMb` (megabytes):
  ```dart
  // before
  maxFileSize: 50 * 1024 * 1024
  // after
  maxFileSizeMb: 50
  ```

### Bug fixes
- Fixed duplicate log entries caused by concurrent flush calls in real-time mode (`bufferSize: 0`). An `_isFlushing` guard with a `Completer` ensures only one flush runs at a time.
- Fixed Dio HTTP log formatting: requests, responses and errors are now written as clean single-line entries (`[REQUEST]`, `[RESPONSE]`, `[HTTP ERROR]`) instead of the multi-line box-drawing output produced by the default talker formatter.
- Fixed log entry detection for size-based rotation: switched from `┌` character detection to ISO-8601 timestamp prefix matching, since the file format never emits box-drawing characters.
- Removed all isolate usage. File operations now run directly on the Dart event loop.

### New features
- `logRequestBody` (default `false`): include the HTTP request body in log entries.
- `maxRequestBodyLength` (default `5000`): truncate request/response body strings beyond this character count.
- `maxFileSizeMb` now accepts `double`, enabling KB-range thresholds (e.g. `maxFileSizeMb: 0.01` ≈ 10 KB).

### Other
- Added 50 unit tests covering config, formatting, file writes, HTTP formatting, retention, size rotation, and the Hive service.

---

## 2.0.0+3

- Removed isolate usage for file operations.
- Added `logRequestBody` and `maxRequestBodyLength` to `TalkerPersistentConfig`.

## 2.0.0+2

- Internal refactoring and stability improvements.

## 2.0.0+1

- Added automatic file size management (`maxFileSize`): when the log file reaches the limit the oldest half is removed automatically. Default limit: 5 MB.

## 2.0.0

### Breaking changes
- New `TalkerPersistentConfig` class replaces individual constructor parameters.
- `bufferSize`, `flushOnError`, `enableFileLogging`, `enableHiveLogging` are now configured via `TalkerPersistentConfig`.

### Added
- Configurable write buffer (`bufferSize: 0` for real-time, `> 0` for batched writes).
- Immediate flush for `error` and `critical` log levels (`flushOnError: true`).
- Selective logging via `enableFileLogging` / `enableHiveLogging`.

## 1.0.0+4

- Initial release with file and Hive database logging support.

## 1.0.0+3

- Fix: write file on Windows.
- Fix: recursive directory creation.

## 1.0.0+2

- Added `maxLines` handling and file rotation.
- Improved write performance with buffering.

## 1.0.0

- Initial version.
