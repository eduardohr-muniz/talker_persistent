// // ignore_for_file: cascade_invocations

// import 'dart:convert';
// import 'package:talker/talker.dart';

// extension PrettyTalker on TalkerData {
//   String toPrettyString() {
//     final buffer = StringBuffer();
//     final borderChar = '─';
//     const maxLineLength = 120;
//     final horizontalBorder = '┌${borderChar * (maxLineLength - 1)}';

//     buffer.writeln(horizontalBorder);

//     // Linha do título e horário
//     buffer.writeln('│ [$title] ${displayTime()}');

//     // Se for um tipo HTTP
//     if (_isHttpLog()) {
//       final message = generateTextMessage();
//       for (final line in _splitLongLines(message)) {
//         buffer.writeln('│ $line');
//       }
//     } else {
//       // Caso contrário, log padrão
//       if (displayMessage.isNotEmpty) {
//         for (final line in _splitLongLines(displayMessage)) {
//           buffer.writeln('│ $line');
//         }
//       }
//     }

//     // Tipo de erro e mensagem
//     if (exception != null || error != null) {
//       final type = exception?.runtimeType.toString() ?? error?.runtimeType.toString();
//       final msg = exception?.toString() ?? error?.toString();
//       buffer.writeln('│');
//       buffer.writeln('│ Type: $type');
//       if (msg != null && msg.isNotEmpty) {
//         buffer.writeln('│ Message: $msg');
//       }
//     }

//     // StackTrace
//     if (stackTrace != null) {
//       buffer.writeln('│');
//       buffer.writeln('│ StackTrace:');
//       for (final line in _splitLongLines(stackTrace.toString(), indent: 2)) {
//         buffer.writeln('│   $line');
//       }
//     }

//     buffer.write('└${borderChar * (maxLineLength - 1)}');

//     return buffer.toString();
//   }

//   // Utilitário para verificar se o log é HTTP
//   bool _isHttpLog() {
//     return [
//       TalkerLogType.httpError.key,
//       TalkerLogType.httpRequest.key,
//       TalkerLogType.httpResponse.key,
//     ].contains(title);
//   }

//   // Divide linhas muito longas em partes menores para caber na largura
//   List<String> _splitLongLines(String text, {int indent = 0}) {
//     const maxLineLength = 110;
//     final lines = <String>[];
//     final prefix = ' ' * indent;

//     final rawLines = const LineSplitter().convert(text);

//     for (final rawLine in rawLines) {
//       var line = rawLine.trimRight();

//       while (line.length > maxLineLength) {
//         lines.add(prefix + line.substring(0, maxLineLength));
//         line = line.substring(maxLineLength);
//       }

//       lines.add(prefix + line);
//     }

//     return lines;
//   }
// }
