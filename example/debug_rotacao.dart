import 'dart:io';
import 'package:talker/talker.dart';
import 'package:talker_persistent/talker_persistent.dart';

void main() async {
  print('=== Debug da Rotação ===');
  await debugRotacao();
}

Future<void> debugRotacao() async {
  final config = TalkerPersistentConfig(
    bufferSize: 0, // Tempo real
    flushOnError: true,
    maxCapacity: 1000,
    enableFileLogging: true,
    enableHiveLogging: false,
    saveAllLogs: false,
    maxFileSizeMb: 0.01, // ~10 KB limit for quick rotation testing
  );

  final history = await TalkerPersistentHistory.create(
    logName: 'debug_rotacao',
    savePath: 'logs',
    config: config,
  );

  final talker = Talker(history: history);

  print('📝 Iniciando debug...');
  print('📏 Limite: 5KB');

  // Gera logs pequenos mas suficientes para atingir 5KB
  for (int i = 1; i <= 20; i++) {
    final logMessage = 'LOG_${i.toString().padLeft(2, '0')}';

    // Cria dados médios para acelerar o teste
    final data = {
      'id': i,
      'message': logMessage,
      'data': 'Dados de teste ' * 50, // Repete 50 vezes
      'timestamp': DateTime.now().toIso8601String(),
      'extra': 'Informação adicional ' * 30,
    };

    talker.info('$logMessage: ${data.toString()}');

    // Verifica o arquivo após cada log
    await Future.delayed(Duration(milliseconds: 200)); // Aguarda escrita

    try {
      final file = File('logs/debug_rotacao.txt');
      if (await file.exists()) {
        final size = await file.length();
        final sizeKB = (size / 1024).toStringAsFixed(2);
        print('📊 Log $i - Tamanho: ${sizeKB}KB ($size bytes)');

        // Verifica se deve ter rotação
        if (size >= 5 * 1024) {
          print('⚠️ DEVERIA TER ROTAÇÃO! Tamanho: ${sizeKB}KB >= 5KB');

          // Lê o arquivo para verificar
          final content = await file.readAsString();
          final logCount = '┌'.allMatches(content).length;
          print('📋 Logs no arquivo: $logCount');

          // Mostra os primeiros e últimos logs
          final lines = content.split('\n');
          final logs = <String>[];
          var currentLog = <String>[];
          var foundLog = false;

          for (var line in lines) {
            if (line.contains('┌')) {
              if (foundLog) {
                logs.add(currentLog.join('\n'));
              }
              currentLog = [line];
              foundLog = true;
            } else if (foundLog) {
              currentLog.add(line);
            }
          }
          if (foundLog) {
            logs.add(currentLog.join('\n'));
          }

          if (logs.isNotEmpty) {
            print('📋 Primeiro log: ${logs.first.substring(0, 100)}...');
            print('📋 Último log: ${logs.last.substring(0, 100)}...');

            // Verifica se há logs antigos ainda presentes
            final primeiroLog = logs.first;
            if (primeiroLog.contains('LOG_01') || primeiroLog.contains('LOG_02')) {
              print('❌ ROTAÇÃO NÃO FUNCIONOU! Logs antigos ainda estão no arquivo');
            } else {
              print('✅ ROTAÇÃO FUNCIONOU! Logs antigos foram removidos');
            }
          }
        }
      }
    } catch (e) {
      print('❌ Erro ao verificar arquivo: $e');
    }
  }

  await history.dispose();
  print('✅ Debug finalizado');
}
