import 'dart:io';
import 'package:talker/talker.dart';
import 'package:talker_persistent/talker_persistent.dart';

void main() async {
  print('=== Teste de Rotação - Limite de 10KB ===');
  await testeRotacao();
}

/// Teste específico para verificar a rotação de logs
Future<void> testeRotacao() async {
  final config = TalkerPersistentConfig(
    bufferSize: 0, // Tempo real
    flushOnError: true,
    maxCapacity: 1000,
    enableFileLogging: true,
    enableHiveLogging: false, // Apenas arquivo
    saveAllLogs: false,
    maxFileSize: 10 * 1024, // 10KB para teste rápido
  );

  final history = await TalkerPersistentHistory.create(
    logName: 'teste_rotacao',
    savePath: 'logs',
    config: config,
  );

  final talker = Talker(history: history);

  print('📝 Iniciando teste de rotação...');
  print('📏 Limite: 10KB');
  print('🔄 Quando atingir 10KB, deve remover a metade mais antiga');

  // Lista para rastrear os logs enviados
  final logsEnviados = <String>[];

  // Gera logs com identificadores únicos
  for (int i = 1; i <= 50; i++) {
    final logMessage = 'LOG_${i.toString().padLeft(3, '0')} - ${DateTime.now().millisecondsSinceEpoch}';
    logsEnviados.add(logMessage);

    // Cria dados grandes para acelerar o teste
    final largeData = {
      'id': i,
      'message': logMessage,
      'data': 'Dados grandes para teste ' * 20, // Repete 20 vezes
      'timestamp': DateTime.now().toIso8601String(),
    };

    talker.info('$logMessage: ${largeData.toString()}');

    // Verifica o arquivo a cada 10 logs
    if (i % 10 == 0) {
      await Future.delayed(Duration(milliseconds: 100)); // Aguarda escrita

      try {
        final file = File('logs/teste_rotacao.txt');
        if (await file.exists()) {
          final size = await file.length();
          final sizeKB = (size / 1024).toStringAsFixed(2);
          print('📊 Log $i - Tamanho: ${sizeKB}KB');

          // Verifica se a rotação aconteceu
          if (size >= 10 * 1024) {
            print('⚠️ Arquivo atingiu 10KB! Verificando rotação...');
            await verificarRotacao(file, logsEnviados);
          }
        }
      } catch (e) {
        print('❌ Erro ao verificar arquivo: $e');
      }
    }

    await Future.delayed(Duration(milliseconds: 50));
  }

  // Verificação final
  await verificarRotacaoFinal();

  await history.dispose();
  print('✅ Teste finalizado');
}

/// Verifica se a rotação removeu os logs mais antigos
Future<void> verificarRotacao(File file, List<String> logsEnviados) async {
  try {
    final content = await file.readAsString();
    final lines = content.split('\n');

    // Extrai os identificadores dos logs no arquivo
    final logsNoArquivo = <String>[];
    for (final line in lines) {
      if (line.contains('LOG_')) {
        final match = RegExp(r'LOG_\d+').firstMatch(line);
        if (match != null) {
          logsNoArquivo.add(match.group(0)!);
        }
      }
    }

    print('📋 Logs no arquivo: ${logsNoArquivo.length}');
    print('📋 Logs enviados: ${logsEnviados.length}');

    if (logsNoArquivo.isNotEmpty) {
      print('📋 Primeiro log no arquivo: ${logsNoArquivo.first}');
      print('📋 Último log no arquivo: ${logsNoArquivo.last}');
      print('📋 Primeiro log enviado: ${logsEnviados.first}');
      print('📋 Último log enviado: ${logsEnviados.last}');

      // Verifica se os logs mais antigos foram removidos
      final primeiroEnviado = logsEnviados.first;
      final primeiroNoArquivo = logsNoArquivo.first;

      if (primeiroEnviado != primeiroNoArquivo) {
        print('✅ ROTAÇÃO FUNCIONOU! Logs antigos foram removidos');
        print('   Primeiro enviado: $primeiroEnviado');
        print('   Primeiro no arquivo: $primeiroNoArquivo');
      } else {
        print('❌ ROTAÇÃO NÃO FUNCIONOU! Logs antigos ainda estão no arquivo');
      }
    }
  } catch (e) {
    print('❌ Erro ao verificar rotação: $e');
  }
}

/// Verificação final do arquivo
Future<void> verificarRotacaoFinal() async {
  try {
    final file = File('logs/teste_rotacao.txt');
    if (await file.exists()) {
      final size = await file.length();
      final sizeKB = (size / 1024).toStringAsFixed(2);
      print('📊 Tamanho final: ${sizeKB}KB');

      if (size <= 10 * 1024) {
        print('✅ Arquivo está dentro do limite de 10KB');
      } else {
        print('❌ Arquivo ainda está acima de 10KB');
      }

      // Mostra os últimos logs no arquivo
      final content = await file.readAsString();
      final lines = content.split('\n');
      final ultimasLinhas = lines.where((line) => line.contains('LOG_')).take(5).toList();

      print('📋 Últimos 5 logs no arquivo:');
      for (final linha in ultimasLinhas) {
        print('   ${linha.substring(0, linha.length > 100 ? 100 : linha.length)}...');
      }
    }
  } catch (e) {
    print('❌ Erro na verificação final: $e');
  }
}
