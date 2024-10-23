import 'package:dio/dio.dart';
import 'package:localstore/localstore.dart';

class LogEntry {
  final String curl;
  final int statusCode;
  final int responseTimeMs;
  final DateTime timestamp;
  final String? error;

  LogEntry({
    required this.curl,
    required this.statusCode,
    required this.responseTimeMs,
    required this.timestamp,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'curl': curl,
    'statusCode': statusCode,
    'responseTimeMs': responseTimeMs,
    'timestamp': timestamp.toIso8601String(),
    'error': error,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      curl: json['curl'],
      statusCode: json['statusCode'],
      responseTimeMs: json['responseTimeMs'],
      timestamp: DateTime.parse(json['timestamp']),
      error: json['error'],
    );
  }
}

class LoggingInterceptor extends Interceptor {
  final _db = Localstore.instance;
  final Map<String, DateTime> _requestTimes = {};

  Future<void> _saveLog(LogEntry entry) async {
    try {
      final docId = DateTime.now().millisecondsSinceEpoch.toString();
      await _db.collection('curl_logs').doc(docId).set(entry.toJson());
    } catch (e) {
      print('Failed to save log: $e');
    }
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final timestamp = DateTime.now();
    _requestTimes[options.path] = timestamp;

    print('🌐 REQUEST[${options.method}] => PATH: ${options.path}');
    print('Timestamp: ${timestamp.toIso8601String()}');
    print('Headers: ${options.headers}');
    print('Query Parameters: ${options.queryParameters}');
    print('Body: ${options.data}');
    
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final endTime = DateTime.now();
    final startTime = _requestTimes[response.requestOptions.path];
    final responseTimeMs = startTime != null 
        ? endTime.difference(startTime).inMilliseconds 
        : -1;

    print('⬅️ RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}');
    print('Response Time: ${responseTimeMs}ms');
    print('Response Data: ${response.data}');

    // Create and save log entry
    final entry = LogEntry(
      //fix bug here
      curl: response.requestOptions.data?.toString() ?? 'No cURL data',
      statusCode: response.statusCode ?? -1,
      responseTimeMs: responseTimeMs,
      timestamp: endTime,
    );
    _saveLog(entry);

    _requestTimes.remove(response.requestOptions.path);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final endTime = DateTime.now();
    final startTime = _requestTimes[err.requestOptions.path];
    final responseTimeMs = startTime != null 
        ? endTime.difference(startTime).inMilliseconds 
        : -1;

    print('❌ ERROR[${err.response?.statusCode}] => PATH: ${err.requestOptions.path}');
    print('Error Message: ${err.message}');
    print('Response Time: ${responseTimeMs}ms');

    // Create and save log entry for errors
    final entry = LogEntry(
      curl: err.requestOptions.data?.toString() ?? 'No cURL data',
      statusCode: err.response?.statusCode ?? -1,
      responseTimeMs: responseTimeMs,
      timestamp: endTime,
      error: err.message,
    );
    _saveLog(entry);

    _requestTimes.remove(err.requestOptions.path);
    handler.next(err);
  }

  // Helper method to get logs for a specific cURL
  Future<List<LogEntry>> getLogsForCurl(String curl) async {
    try {
      final logs = await _db.collection('curl_logs').get();
      if (logs == null) return [];

      return logs.entries
          .map((e) => LogEntry.fromJson(e.value))
          .where((log) => log.curl == curl)
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      print('Failed to get logs: $e');
      return [];
    }
  }

  // Helper method to clear old logs
  Future<void> clearOldLogs({Duration? olderThan}) async {
    try {
      final logs = await _db.collection('curl_logs').get();
      if (logs == null) return;

      final cutoffDate = DateTime.now().subtract(olderThan ?? const Duration(days: 7));

      for (var entry in logs.entries) {
        final log = LogEntry.fromJson(entry.value);
        if (log.timestamp.isBefore(cutoffDate)) {
          await _db.collection('curl_logs').doc(entry.key).delete();
        }
      }
    } catch (e) {
      print('Failed to clear old logs: $e');
    }
  }
}