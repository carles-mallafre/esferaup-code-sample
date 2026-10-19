import 'package:intl/intl.dart';

String formatFileSize(int bytes, String locale) {
  if (bytes < 1024) return '$bytes B';
  final oneDecimal = NumberFormat('0.0', locale);
  if (bytes < 1024 * 1024) return '${oneDecimal.format(bytes / 1024)} KB';
  return '${oneDecimal.format(bytes / (1024 * 1024))} MB';
}
