import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:talker/talker.dart';
import 'package:talker_persistent/talker_persistent.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Flutter Demo', theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple)), home: const MyHomePage(title: 'Flutter Demo Home Page'));
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final int _counter = 0;

  Future<void> _incrementCounter() async {
    try {
      // Initialize Hive
      final directory = await getApplicationDocumentsDirectory();
      print('\n📂 Diretório base do aplicativo:');
      print(directory.path);

      final hivePath = path.join(directory.path);
      print('\n🏠 Caminho completo para o Hive:');
      print(hivePath);

      await Directory(hivePath).create(recursive: true);

      // Initialize TalkerPersistent with the log name we'll use
      await TalkerPersistent.instance.initialize(
        path: hivePath,
        logNames: {'logzinho'},
      );

      // Create logs directory in the example folder
      final logsPath = path.join(hivePath, 'log');
      print('\n📝 Caminho para os logs:');
      print(logsPath);
      print('\n💡 Para encontrar o arquivo no Finder:');
      print('1. Abra o Finder');
      print('2. Pressione Cmd + Shift + G');
      print('3. Cole o caminho acima');

      print('\n🔍 Verificando diretório...');
      await Directory(logsPath).create(recursive: true);

      final dirExists = await Directory(logsPath).exists();
      print('📁 Diretório existe? $dirExists');

      // Initialize Talker with persistent history
      print('🔄 Iniciando TalkerPersistentHistory...');
      final history = await TalkerPersistentHistory.create(
        logName: 'biel',
        savePath: logsPath,
        maxCapacity: 100,
      );
      print('✅ TalkerPersistentHistory inicializado');

      final talker = Talker(
        history: history,
        settings: TalkerSettings(
          useHistory: true,
        ),
      );

      // Test different types of logs
      talker.debug('This is a debug message');
      talker.info('Application started');
      talker.warning('This is a warning message');
      talker.error('This is an error message', Exception('Test error'));

      // Test history retrieval
      print('\nCurrent history:');
      for (final log in history.history) {
        print('- ${log.displayMessage}');
      }

      final logFile = File(path.join(logsPath, 'biel.log'));
      print('\n📄 Arquivo de log:');
      print(logFile.path);

      if (await logFile.exists()) {
        print('✅ Arquivo encontrado!');
        final stat = await logFile.stat();
        print('📊 Tamanho: ${stat.size} bytes');
        print('⏰ Última modificação: ${stat.modified}');
        print('\n📝 Conteúdo do arquivo:');
        print(await logFile.readAsString());
      } else {
        print('❌ Arquivo não encontrado!');
        print('Verifique se você tem permissões para acessar o diretório.');
      }

      // Clean up
      // await history.dispose();

      print('\n✨ Exemplo finalizado com sucesso!');
    } catch (e, stack) {
      print('Error running example: $e');
      print('Stack trace: $stack');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Theme.of(context).colorScheme.inversePrimary, title: Text(widget.title)),
      body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[const Text('You have pushed the button this many times:'), Text('$_counter', style: Theme.of(context).textTheme.headlineMedium)])),
      floatingActionButton: FloatingActionButton(onPressed: _incrementCounter, tooltip: 'Increment', child: const Icon(Icons.add)),
    );
  }
}
