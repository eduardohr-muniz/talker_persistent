/// Benchmark for TalkerPersistentHistory write throughput.
///
/// Run with:
///   dart run example/benchmark.dart
import 'dart:io';

import 'package:talker/talker.dart';
import 'package:talker_persistent/talker_persistent.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Config
// ─────────────────────────────────────────────────────────────────────────────

const _writesPerScenario = 500;
const _maxCapacity = 1000;

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  print('╔══════════════════════════════════════════════════════════╗');
  print('║         TalkerPersistent — Write Throughput Bench        ║');
  print('╚══════════════════════════════════════════════════════════╝');
  print('  Writes per scenario : $_writesPerScenario');
  print('  maxCapacity         : $_maxCapacity');
  print('');

  final results = <_Result>[];

  // 1. Real-time — cold (empty file)
  results.add(await _run(
    label: 'bufferSize=0   | cold (empty file)',
    bufferSize: 0,
    preloadEntries: 0,
  ));

  // 2. Real-time — warm file near capacity (most common real-world state)
  results.add(await _run(
    label: 'bufferSize=0   | warm (900 entries ≈ 90% capacity)',
    bufferSize: 0,
    preloadEntries: 900,
  ));

  // 3. Real-time — file over capacity (triggers _rotateLogFile)
  results.add(await _run(
    label: 'bufferSize=0   | over capacity (1100 entries)',
    bufferSize: 0,
    preloadEntries: 1100,
  ));

  // 4. Batched 10 — cold
  results.add(await _run(
    label: 'bufferSize=10  | cold (empty file)',
    bufferSize: 10,
    preloadEntries: 0,
  ));

  // 5. Batched 100 — cold
  results.add(await _run(
    label: 'bufferSize=100 | cold (empty file)',
    bufferSize: 100,
    preloadEntries: 0,
  ));

  // 6. Batched 100 — warm
  results.add(await _run(
    label: 'bufferSize=100 | warm (900 entries)',
    bufferSize: 100,
    preloadEntries: 900,
  ));

  // ── Summary table ──────────────────────────────────────────────────────────
  print('');
  print('┌─────────────────────────────────────────────────────────────────────');
  print('│ Results');
  print('├──────────────────────────────────────────────────────┬──────────┬────────────┬───────────');
  print('│ Scenario                                             │ Total ms │ writes/sec │ File size');
  print('├──────────────────────────────────────────────────────┼──────────┼────────────┼───────────');
  for (final r in results) {
    final label = r.label.padRight(52);
    final ms = r.elapsedMs.toString().padLeft(8);
    final wps = r.writesPerSec.toStringAsFixed(0).padLeft(10);
    final size = _formatBytes(r.finalFileSizeBytes).padLeft(9);
    print('│ $label │ $ms │ $wps │ $size');
  }
  print('└──────────────────────────────────────────────────────┴──────────┴────────────┴───────────');
  print('');
}

// ─────────────────────────────────────────────────────────────────────────────
// Benchmark runner
// ─────────────────────────────────────────────────────────────────────────────

Future<_Result> _run({
  required String label,
  required int bufferSize,
  required int preloadEntries,
}) async {
  final dir = await Directory.systemTemp.createTemp('tp_bench_');
  try {
    // Pre-populate the file with valid timestamp entries if requested.
    // Each entry is ~100 bytes so 1100 entries ≈ 110 KB.
    if (preloadEntries > 0) {
      final logFile = File('${dir.path}/bench.log');
      final lines = List.generate(
        preloadEntries,
        (i) =>
            '2024-01-01T00:00:00.000000 [INFO] preload-${i.toString().padLeft(4, '0')} payload',
      ).join('\n');
      await logFile.writeAsString('$lines\n');
    }

    final h = await TalkerPersistentHistory.create(
      logName: 'bench',
      savePath: dir.path,
      config: TalkerPersistentConfig(
        bufferSize: bufferSize,
        enableHiveLogging: false,
        maxCapacity: _maxCapacity,
        maxFileSizeMb: 50.0, // large enough to never trigger size rotation
      ),
    );

    final sw = Stopwatch()..start();

    for (var i = 0; i < _writesPerScenario; i++) {
      h.write(TalkerLog(
        'bench-msg-${i.toString().padLeft(4, '0')} some payload data here',
        logLevel: LogLevel.info,
      ));
    }

    await h.dispose();
    sw.stop();

    final logFile = File('${dir.path}/bench.log');
    final fileSize = await logFile.exists() ? await logFile.length() : 0;

    final elapsedMs = sw.elapsedMilliseconds;
    final wps = _writesPerScenario / (elapsedMs / 1000.0);

    print('  ✓  $label  →  ${elapsedMs}ms  (${wps.toStringAsFixed(0)} writes/sec)');

    return _Result(
      label: label,
      elapsedMs: elapsedMs,
      writesPerSec: wps,
      finalFileSizeBytes: fileSize,
    );
  } finally {
    await dir.delete(recursive: true);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _Result {
  final String label;
  final int elapsedMs;
  final double writesPerSec;
  final int finalFileSizeBytes;

  const _Result({
    required this.label,
    required this.elapsedMs,
    required this.writesPerSec,
    required this.finalFileSizeBytes,
  });
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '${bytes}B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)}MB';
}
