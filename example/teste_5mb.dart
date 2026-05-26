import 'dart:io';
import 'package:talker/talker.dart';
import 'package:talker_persistent/talker_persistent.dart';

void main() async {
  print('=== Teste do limite de 5MB ===');
  await testeLimite5MB();
}

/// Teste específico para o limite de 5MB
Future<void> testeLimite5MB() async {
  final config = TalkerPersistentConfig(
    bufferSize: 0, // Tempo real para garantir escrita imediata
    flushOnError: true,
    maxCapacity: 10000, // Capacidade alta
    enableFileLogging: true,
    enableHiveLogging: false, // Apenas arquivo para o teste
    saveAllLogs: false, // Não usar saveAllLogs para este teste
    maxFileSizeMb: 5,
  );

  final history = await TalkerPersistentHistory.create(
    logName: 'teste_5mb',
    savePath: 'logs',
    config: config,
  );

  final talker = Talker(history: history);

  print('📝 Iniciando teste de limite de 5MB...');
  print('📏 Tamanho máximo configurado: 5MB');
  print('🔄 Quando atingir 5MB, a metade mais antiga será removida automaticamente');

  // Gera logs grandes para atingir rapidamente o limite de 5MB
  for (int i = 1; i <= 1000; i++) {
    // Cria um log com dados grandes para acelerar o teste
    final largeData = {
      'id': i,
      'timestamp': DateTime.now().toIso8601String(),
      'data': 'Dados de teste muito grandes ' * 100, // Repete 100 vezes
      'details': {
        'field1': 'valor1' * 50,
        'field2': 'valor2' * 50,
        'field3': 'valor3' * 50,
        'nested': {
          'deep1': 'dados profundos ' * 30,
          'deep2': 'mais dados ' * 30,
        }
      },
      'array': List.generate(50, (index) => 'item_$index' * 10),
    };

    talker.info('Log grande $i: ${largeData.toString()}');

    // Verifica o tamanho do arquivo a cada 100 logs
    if (i % 100 == 0) {
      try {
        final file = File('logs/teste_5mb.txt');
        if (await file.exists()) {
          final size = await file.length();
          final sizeMB = (size / (1024 * 1024)).toStringAsFixed(2);
          print('📊 Log $i - Tamanho atual: ${sizeMB}MB');

          // Se atingiu 5MB, mostra que a rotação deve acontecer
          if (size >= 5 * 1024 * 1024) {
            print('⚠️ Arquivo atingiu 5MB! A rotação deve acontecer no próximo log.');
          }
        }
      } catch (e) {
        print('❌ Erro ao verificar tamanho: $e');
      }
    }

    // Pequena pausa para não sobrecarregar
    await Future.delayed(Duration(milliseconds: 10));
  }

  // Verificação final
  try {
    final file = File('logs/teste_5mb.txt');
    if (await file.exists()) {
      final size = await file.length();
      final sizeMB = (size / (1024 * 1024)).toStringAsFixed(2);
      print('📊 Tamanho final do arquivo: ${sizeMB}MB');

      if (size <= 5 * 1024 * 1024) {
        print('✅ Teste concluído! Arquivo está dentro do limite de 5MB');
      } else {
        print('❌ Arquivo ainda está acima de 5MB - verificar implementação');
      }
    }
  } catch (e) {
    print('❌ Erro na verificação final: $e');
  }

  await history.dispose();
  print('✅ Teste finalizado');
}
