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

/// Todas operações de arquivo são realizadas diretamente na thread principal.

/// Classe para gerenciar um arquivo de log específico
class _LogFileManager {
  final String filePath;
  final bool saveAllLogs;
  final LogRetentionPeriod? logRetentionPeriod;
  final int? maxFileSize;

  File? logFile;
  int currentLogCount = 0;
  String? currentDate;
  int fileCounter = 1;
  String? baseName;

  _LogFileManager({
    required this.filePath,
    required this.saveAllLogs,
    this.logRetentionPeriod,
    this.maxFileSize,
  });

  Future<void> initialize() async {
    try {
      if (filePath.isEmpty) {
        throw Exception('File path cannot be empty');
      }

      baseName = path.basenameWithoutExtension(filePath);
      if (baseName == null || baseName!.isEmpty) {
        baseName = 'log';
      }

      if (saveAllLogs) {
        final now = DateTime.now();
        currentDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
        final basePath = path.dirname(filePath);
        final dailyFilePath = path.join(basePath, '$baseName-$currentDate.$_extension');
        logFile = File(dailyFilePath);
        await deleteOldFiles();
      } else {
        logFile = File(filePath);
      }

      if (logFile == null) {
        throw Exception('Failed to create log file instance');
      }

      // Criar diretório pai de forma segura
      try {
        await logFile!.parent.create(recursive: true);
      } catch (e) {
        // Continuar mesmo se falhar, pode ser que já exista
      }

      // Verificar e criar arquivo de forma segura
      if (await logFile!.exists()) {
        try {
          final content = await logFile!.readAsString();
          currentLogCount = '┌'.allMatches(content).length;
        } catch (e) {
          currentLogCount = 0;
        }
      } else {
        try {
          await logFile!.writeAsString('');
          currentLogCount = 0;
        } catch (e) {
          currentLogCount = 0;
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> deleteOldFiles() async {
    if (logRetentionPeriod == null || baseName == null) return;

    try {
      final basePath = logFile?.parent.path;
      if (basePath == null) return;

      final dir = Directory(basePath);
      if (await dir.exists()) {
        final files = await dir.list().toList();
        final now = DateTime.now();
        Duration retention;
        switch (logRetentionPeriod) {
          case LogRetentionPeriod.threeDays:
            retention = Duration(days: 3);
            break;
          case LogRetentionPeriod.week:
            retention = Duration(days: 7);
            break;
          case LogRetentionPeriod.fortnight:
            retention = Duration(days: 15);
            break;
          case LogRetentionPeriod.month:
            retention = Duration(days: 31);
            break;
          case null:
            retention = Duration(days: 3650); // 10 anos, fallback
            break;
        }

        for (final f in files) {
          if (f is File && f.path.contains(baseName!) && f.path.endsWith('.$_extension')) {
            final regex = RegExp(r'(\d{4})-(\d{2})-(\d{2})');
            final match = regex.firstMatch(f.path);
            if (match != null) {
              final fileDate = DateTime(
                int.parse(match.group(1)!),
                int.parse(match.group(2)!),
                int.parse(match.group(3)!),
              );
              if (now.difference(fileDate) > retention) {
                await f.delete();
              }
            }
          }
        }
      }
    } catch (e) {
      // Ignora erros na deleção
    }
  }

  Future<void> write(List<String> logs) async {
    try {
      if (logFile == null || logs.isEmpty) {
        return;
      }

      // Verifica se mudou o dia quando saveAllLogs está ativo
      if (saveAllLogs) {
        try {
          final now = DateTime.now();
          final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

          if (currentDate != today) {
            currentDate = today;
            final basePath = logFile!.parent.path;
            final dailyFilePath = path.join(basePath, '$baseName-$currentDate.$_extension');
            logFile = File(dailyFilePath);
            currentLogCount = 0;
            fileCounter = 1;
            await deleteOldFiles();
          }
        } catch (e) {
          // Continuar com o arquivo atual
        }
      }

      final content = '${logs.join('\n')}\n';
      final newLogCount = '┌'.allMatches(content).length;

      // Verifica se precisa rotacionar por tamanho - com proteção
      if (maxFileSize != null) {
        try {
          if (await logFile!.exists()) {
            final fileSize = await logFile!.length();
            if (fileSize + content.length > maxFileSize!) {
              await _rotateFileBySize();
            }
          }
        } catch (e) {
          // Continuar sem rotação
        }
      }

      // Para saveAllLogs, sempre adiciona ao final do arquivo - com proteção
      try {
        await logFile!.writeAsString(content, mode: FileMode.append);
        currentLogCount += newLogCount;
      } catch (e) {
        // Tentar recovery - criar novo arquivo se necessário
        try {
          await logFile!.parent.create(recursive: true);
          await logFile!.writeAsString(content, mode: FileMode.write);
          currentLogCount = newLogCount;
        } catch (recoveryError) {
          throw Exception('Failed to write log and recovery failed: $e -> $recoveryError');
        }
      }
    } catch (e) {
      // NÃO fazer rethrow aqui para evitar crash do isolate
      // O erro já foi logado, melhor continuar funcionando
    }
  }

  /// Rotaciona o arquivo removendo a metade mais antiga quando atinge o tamanho máximo
  Future<void> _rotateFileBySize() async {
    if (maxFileSize == null || !await logFile!.exists()) return;

    try {
      final content = await logFile!.readAsString();
      final lines = content.split('\n');
      final logs = <String>[];
      var currentLog = <String>[];
      var foundLog = false;

      // Separa os logs individuais
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

      // Remove a metade mais antiga
      final keepCount = (logs.length / 2).ceil();
      final keepLogs = logs.skip(logs.length - keepCount).toList();

      // Cria novo arquivo com apenas os logs mais recentes
      final newContent = keepLogs.join('\n');
      await logFile!.writeAsString(newContent);

      // Atualiza o contador de logs
      currentLogCount = '┌'.allMatches(newContent).length;
    } catch (e) {
      log(e.toString(), name: 'TalkerPersistentHistory');
    }
  }

  Future<String> read() async {
    if (logFile == null) return '';
    return await logFile!.readAsString();
  }

  Future<void> dispose() async {
    logFile = null;
    currentLogCount = 0;
    currentDate = null;
    baseName = null;
  }
}

/// Enum para definir o período de retenção dos arquivos de log
enum LogRetentionPeriod {
  threeDays,
  week,
  fortnight,
  month,
}

/// Configuration class for TalkerPersistentHistory
class TalkerPersistentConfig {
  /// Buffer size for logs. If 0, logs are written immediately (real-time).
  /// If > 0, logs are buffered and written when buffer is full.
  final int bufferSize;

  /// Whether to flush immediately for error and critical logs
  final bool flushOnError;

  /// Maximum capacity of logs to keep
  final int maxCapacity;

  /// Whether to enable file logging
  final bool enableFileLogging;

  /// Whether to enable Hive database logging
  final bool enableHiveLogging;

  /// Whether to save all logs of the day in a daily file
  /// When true, logs will be saved in files named as 'logName-YYYY-MM-DD.$_extension'
  final bool saveAllLogs;

  /// Período de retenção dos arquivos de log (usado com saveAllLogs)
  final LogRetentionPeriod logRetentionPeriod;

  /// Tamanho máximo do arquivo de log em bytes (padrão: 5MB)
  /// Quando o arquivo atinge este tamanho, um novo arquivo é criado
  final int maxFileSize;

  /// Whether to log request body in HTTP logs
  /// When true, request body will be included in [REQUEST] logs
  final bool logRequestBody;

  /// Maximum length in characters for request body logging
  /// If the body exceeds this length, it will be truncated
  final int maxRequestBodyLength;

  // Isolates removidos: todas operações são diretas na thread principal

  const TalkerPersistentConfig({
    this.bufferSize = 100,
    this.flushOnError = true,
    this.maxCapacity = 1000,
    this.enableFileLogging = true,
    this.enableHiveLogging = true,
    this.saveAllLogs = false,
    this.logRetentionPeriod = LogRetentionPeriod.threeDays,
    this.maxFileSize = 5 * 1024 * 1024, // 5MB
    this.logRequestBody = false,
    this.maxRequestBodyLength = 5000, // 5000 caracteres por padrão
  });

  TalkerPersistentConfig copyWith({
    int? bufferSize,
    bool? flushOnError,
    int? maxCapacity,
    bool? enableFileLogging,
    bool? enableHiveLogging,
    bool? saveAllLogs,
    LogRetentionPeriod? logRetentionPeriod,
    int? maxFileSize,
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
      logRetentionPeriod: logRetentionPeriod ?? this.logRetentionPeriod,
      maxFileSize: maxFileSize ?? this.maxFileSize,
      logRequestBody: logRequestBody ?? this.logRequestBody,
      maxRequestBodyLength: maxRequestBodyLength ?? this.maxRequestBodyLength,
    );
  }
}

/// A persistent implementation of [TalkerHistory] that stores logs on disk using Hive.
/// This implementation works for both Dart and Flutter applications.
class TalkerPersistentHistory implements TalkerHistory {
  final String logName;
  final String? savePath;
  final TalkerPersistentConfig config;

  final List<String> _writeBuffer = [];
  bool _isInitialized = false;

  // Manager de arquivo direto (sem isolate)
  _LogFileManager? _directFileManager;

  /// Creates a new instance of [TalkerPersistentHistory].
  ///
  /// [logName] unique identifier for this history instance.
  /// [savePath] optional path to save logs to a file. If provided, logs will be written to both Hive and the file.
  /// [config] configuration for the persistent history behavior.
  TalkerPersistentHistory({
    required this.logName,
    this.savePath,
    TalkerPersistentConfig? config,
  }) : config = config ?? const TalkerPersistentConfig();

  /// Initializes the persistent storage.
  /// This method must be called before using any other methods.
  Future<void> _initialize() async {
    try {
      if (savePath != null && config.enableFileLogging) {
        final logFilePath = path.join(savePath!, '$logName.$_extension');

        if (!_isInitialized) {
          try {
            _directFileManager = _LogFileManager(
              filePath: logFilePath,
              saveAllLogs: config.saveAllLogs,
              logRetentionPeriod: config.logRetentionPeriod,
              maxFileSize: config.maxFileSize,
            );
            await _directFileManager!.initialize();

            _isInitialized = true;
          } catch (e) {
            _isInitialized = false;
            // NÃO fazer rethrow para evitar crash do app
          }
        } else {}
      } else {
        if (savePath == null) {}
        if (!config.enableFileLogging) {}
      }
    } catch (e) {
      _isInitialized = false;
      // NÃO fazer rethrow aqui para evitar crash do app
      // É melhor o app continuar funcionando sem logging do que crashar
    }
  }

  /// Creates a new instance of [TalkerPersistentHistory].
  static Future<TalkerPersistentHistory> create({
    required String logName,
    String? savePath,
    TalkerPersistentConfig? config,
  }) async {
    final history = TalkerPersistentHistory(
      logName: logName,
      savePath: savePath,
      config: config,
    );
    await history._initialize();
    return history;
  }

  /// Rotates the log file by keeping only the most recent logs
  Future<void> _rotateLogFile() async {
    if (!config.enableFileLogging || config.saveAllLogs) return;

    try {
      String? content;

      // Usar leitura direta
      if (_directFileManager != null) {
        content = await _directFileManager!.read();
      }

      if (content != null) {
        final logCount = '┌'.allMatches(content).length;

        if (logCount > config.maxCapacity) {
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

          final skipCount = math.max(0, logs.length - config.maxCapacity);
          final keepLogs = logs.skip(skipCount).toList();

          await _directFileManager!.write(keepLogs);
        }
      }
    } catch (e) {
      log(e.toString(), name: 'TalkerPersistentHistory');
    }
  }

  /// Flushes the write buffer to disk
  Future<void> _flushBuffer() async {
    if (_writeBuffer.isEmpty || !_isInitialized || !config.enableFileLogging) return;

    // Criar cópia do buffer para evitar modificações concorrentes
    List<String> bufferCopy;
    try {
      bufferCopy = List.from(_writeBuffer);
    } catch (e) {
      _writeBuffer.clear();
      return;
    }

    try {
      // Usar escrita direta na thread principal
      if (_directFileManager != null) {
        await _directFileManager!.write(bufferCopy);
      } else {
        return;
      }

      // Só limpar buffer se escrita foi bem-sucedida
      _writeBuffer.clear();
    } catch (e) {
      // Emergency buffer clear para evitar memory leak
      if (_writeBuffer.length > 1000) {
        _writeBuffer.clear();
      }

      // NÃO fazer rethrow - é melhor perder logs do que crashar
    }
  }

  /// Checks if a log level requires immediate flush
  bool _shouldFlushImmediately(TalkerData data) {
    if (!config.flushOnError) return false;
    return data.logLevel == LogLevel.error || data.logLevel == LogLevel.critical;
  }

  String formatLogSimple(TalkerData data) {
    final timestamp = data.time.toIso8601String();
    final level = data.logLevel?.name.toUpperCase() ?? 'UNKNOWN';
    String msg = (data.message ?? '').replaceAll(RegExp(r'[\r\n]+'), ' ');

    // Para logs HTTP, criar logs separados para requisição e body
    if (_isHttpLog(data)) {
      final body = _extractHttpBody(data);

      // Se tem body, retorna apenas o body (a requisição será logada separadamente)
      if (body.isNotEmpty && body != msg) {
        return '$timestamp [$level] [BODY]: $body';
      }

      // Se não tem body ou é igual à mensagem, retorna como requisição
      return '$timestamp [$level] [REQUEST] $msg';
    }

    // Trunca mensagens muito longas
    if (msg.length > 800) {
      msg = '${msg.substring(0, 800)}...';
    }

    if (data.logLevel == LogLevel.error || data.logLevel == LogLevel.critical) {
      final stack = data.stackTrace?.toString().replaceAll(RegExp(r'[\r\n]+'), ' ') ?? '';
      return '$timestamp [$level] $msg${stack.isNotEmpty ? ' [STACK] $stack' : ''}';
    }
    return '$timestamp [$level] $msg';
  }

  bool _isHttpLog(TalkerData data) {
    // Verificar se é um DioResponseLog
    if (data is DioResponseLog) {
      return true;
    }

    // Verificar por título
    final title = data.title?.toLowerCase() ?? '';
    return [
      'httperror',
      'httprequest',
      'httpresponse',
      'http-request',
      'http-response',
      'http-error',
    ].contains(title);
  }

  bool _isValidRequestBodyType(dynamic data) {
    // Só aceita Map ou List de Map
    if (data is Map) {
      return true;
    }
    if (data is List) {
      // Verifica se todos os elementos são Map
      if (data.isEmpty) return true; // Lista vazia é válida
      return data.every((item) => item is Map);
    }
    return false;
  }

  String _extractHttpRequestBody(TalkerData data) {
    try {
      // Se é DioResponseLog, extrair do requestOptions.data
      if (data is DioResponseLog) {
        final requestData = data.response.requestOptions.data;
        if (requestData != null) {
          // Só processa se for Map ou List de Map, ignora bytes, strings, etc
          if (_isValidRequestBodyType(requestData)) {
            try {
              final bodyString = requestData.toString();
              // Limita o tamanho conforme configuração
              if (bodyString.length > config.maxRequestBodyLength) {
                return '${bodyString.substring(0, config.maxRequestBodyLength)}... [truncated ${bodyString.length - config.maxRequestBodyLength} chars]';
              }
              return bodyString;
            } catch (e) {
              return '';
            }
          }
        }
      }

      // Tentar extrair da mensagem usando regex (para logs de requisição que não são DioResponseLog)
      final message = data.message ?? '';

      // Padrão para "Data: {...}" ou "Body: {...}" - só captura Map ou List
      final patterns = [
        RegExp(r'Data:\s*(\{.*?\}|\[.*?\])', dotAll: true),
        RegExp(r'Body:\s*(\{.*?\}|\[.*?\])', dotAll: true),
        RegExp(r'Request Body:\s*(\{.*?\}|\[.*?\])', dotAll: true),
        RegExp(r'POST.*?Data:\s*(\{.*?\}|\[.*?\])', dotAll: true),
        RegExp(r'PUT.*?Data:\s*(\{.*?\}|\[.*?\])', dotAll: true),
        RegExp(r'PATCH.*?Data:\s*(\{.*?\}|\[.*?\])', dotAll: true),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(message);
        if (match != null && match.group(1) != null) {
          final extracted = match.group(1)!;
          // Limita o tamanho conforme configuração
          if (extracted.length > config.maxRequestBodyLength) {
            return '${extracted.substring(0, config.maxRequestBodyLength)}... [truncated ${extracted.length - config.maxRequestBodyLength} chars]';
          }
          return extracted;
        }
      }

      // Tentar capturar JSON completo na mensagem (só Map ou List)
      final jsonPattern = RegExp(r'(\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}|\[[^\[\]]*(?:\[[^\[\]]*\][^\[\]]*)*\])', dotAll: true);
      final jsonMatch = jsonPattern.firstMatch(message);
      if (jsonMatch != null) {
        final extracted = jsonMatch.group(1)!;
        // Limita o tamanho conforme configuração
        if (extracted.length > config.maxRequestBodyLength) {
          return '${extracted.substring(0, config.maxRequestBodyLength)}... [truncated ${extracted.length - config.maxRequestBodyLength} chars]';
        }
        return extracted;
      }

      return '';
    } catch (e) {
      return '';
    }
  }

  String _extractHttpBody(TalkerData data) {
    try {
      final message = data.message ?? '';

      // Tentar extrair diretamente do DioResponseLog se disponível
      if (data is DioResponseLog) {
        final response = data.response;
        if (response.data != null) {
          final responseData = response.data;

          // Verificar se não é bytes e não é muito grande
          if (responseData is! List<int> && responseData.toString().length < 1000) {
            return responseData.toString();
          }
        }
      }

      // Extrair body da requisição (formato do TalkerDioLogger)
      final requestBodyMatch = RegExp(r'Data:\s*(\{.*?\}|\[.*?\]|"[^"]*"|\S+)', dotAll: true).firstMatch(message);
      if (requestBodyMatch != null) {
        return requestBodyMatch.group(1) ?? '';
      }

      // Extrair body da resposta (formato do TalkerDioLogger)
      final responseBodyMatch = RegExp(r'Data:\s*(\{.*?\}|\[.*?\]|"[^"]*"|\S+)', dotAll: true).firstMatch(message);
      if (responseBodyMatch != null) {
        return responseBodyMatch.group(1) ?? '';
      }

      // Extrair body da requisição (outros formatos)
      final requestBodyMatch2 = RegExp(r'Body:\s*(\{.*?\}|\[.*?\]|"[^"]*"|\S+)', dotAll: true).firstMatch(message);
      if (requestBodyMatch2 != null) {
        return requestBodyMatch2.group(1) ?? '';
      }

      // Extrair body da resposta (outros formatos)
      final responseBodyMatch2 = RegExp(r'Response:\s*(\{.*?\}|\[.*?\]|"[^"]*"|\S+)', dotAll: true).firstMatch(message);
      if (responseBodyMatch2 != null) {
        return responseBodyMatch2.group(1) ?? '';
      }

      // Tentar capturar JSON/objetos diretamente
      final jsonMatch = RegExp(r'(\{[^{}]*\}|\[[\[\]]*\])', dotAll: true).firstMatch(message);
      if (jsonMatch != null) {
        return jsonMatch.group(1) ?? '';
      }

      // Tentar capturar strings entre aspas
      final stringMatch = RegExp(r'"([^"]*)"').firstMatch(message);
      if (stringMatch != null) {
        return stringMatch.group(1) ?? '';
      }

      // Se não encontrou nada, retorna a mensagem inteira (URL ou o que vier)
      return message;
    } catch (e) {
      return data.message ?? '';
    }
  }

  @override
  void write(TalkerData data) {
    // Write to Hive if enabled
    if (config.enableHiveLogging) {
      TalkerPersistent.instance.write(
        data: data,
        logName: logName,
        maxCapacity: config.maxCapacity,
      );
    }

    // Write to file if enabled
    if (_isInitialized && config.enableFileLogging) {
      try {
        // Para logs HTTP, criar logs separados para requisição e resposta
        if (_isHttpLog(data)) {
          final body = _extractHttpBody(data);
          final timestamp = data.time.toIso8601String();
          final level = data.logLevel?.name.toUpperCase() ?? 'UNKNOWN';
          final msg = (data.message ?? '').replaceAll(RegExp(r'[\r\n]+'), ' ');

          // Determinar se é REQUEST ou RESPONSE
          // DioResponseLog sempre é uma resposta, mas contém info da requisição também
          // Se não é DioResponseLog mas tem título "response", é resposta
          // Caso contrário, é requisição
          final isResponse = data is DioResponseLog || (data.title?.toLowerCase().contains('response') == true);

          if (isResponse) {
            // Para DioResponseLog, logar primeiro a requisição (se logRequestBody estiver ativo)
            if (data is DioResponseLog && config.logRequestBody) {
              final requestOptions = data.response.requestOptions;
              final requestUrl = requestOptions.uri.toString();
              final requestBody = _extractHttpRequestBody(data);

              String requestLog = '$timestamp [$level] [REQUEST] $requestUrl';
              if (requestBody.isNotEmpty) {
                requestLog += '\n$timestamp [$level] [REQUEST BODY]: $requestBody';
              }
              _writeBuffer.add(requestLog);
            }

            // Para respostas, mostrar [RESPONSE]: com os dados
            if (body.isNotEmpty && body != msg) {
              final responseLog = '$timestamp [$level] [RESPONSE]: $body';
              _writeBuffer.add(responseLog);
            } else {
              // Se não tem body, mostrar como resposta normal
              final responseLog = '$timestamp [$level] [RESPONSE] $msg';
              _writeBuffer.add(responseLog);
            }
          } else {
            // Para requisições (não DioResponseLog), mostrar [REQUEST] com a URL
            String requestLog = '$timestamp [$level] [REQUEST] $msg';

            // Se logRequestBody está ativo, adicionar o body da requisição
            if (config.logRequestBody) {
              final requestBody = _extractHttpRequestBody(data);
              if (requestBody.isNotEmpty) {
                requestLog += '\n$timestamp [$level] [REQUEST BODY]: $requestBody';
              }
            }

            _writeBuffer.add(requestLog);
          }
        } else {
          // Log normal (não HTTP)
          final formattedLog = formatLogSimple(data);
          _writeBuffer.add(formattedLog);
        }

        // Check if we should flush immediately
        final shouldFlush = config.bufferSize == 0 || // Real-time mode
            _shouldFlushImmediately(data) || // Error/critical logs
            _writeBuffer.length >= config.bufferSize; // Buffer full

        if (shouldFlush) {
          _flushBuffer();
          if (!config.saveAllLogs) {
            _rotateLogFile();
          }
        }
      } catch (e) {
        // Tentar recovery - desabilitar file logging se houver muitos erros
        try {
          if (_writeBuffer.length > 1000) {
            _writeBuffer.clear();
          }
        } catch (bufferError) {
          log(bufferError.toString(), name: 'TalkerPersistentHistory');
        }

        // NÃO fazer rethrow - é melhor perder alguns logs do que crashar o app
      }
    }
  }

  @override
  void clean() {
    if (config.enableHiveLogging) {
      TalkerPersistent.instance.clean(logName: logName);
    }
  }

  @override
  List<TalkerData> get history {
    if (!config.enableHiveLogging) return [];
    return List.unmodifiable(TalkerPersistent.instance.getLogs(logName: logName));
  }

  /// Disposes of the resources used by this instance.
  Future<void> dispose() async {
    if (_isInitialized && config.enableFileLogging) {
      if (_writeBuffer.isNotEmpty) {
        await _flushBuffer();
      }

      // Dispose do direct file manager
      if (_directFileManager != null) {
        await _directFileManager!.dispose();
        _directFileManager = null;
      }

      _isInitialized = false;
    }

    // Fecha o Hive se estiver habilitado
    if (config.enableHiveLogging) {
      try {
        await Hive.close();
      } catch (e) {
        log(e.toString(), name: 'TalkerPersistentHistory');
      }
    }
  }
}
