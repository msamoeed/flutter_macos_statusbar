import 'package:dio/dio.dart';
import 'package:localstore/localstore.dart';

class RequestStats {
  int totalRequests;
  int successfulRequests;
  int failedRequests;
  int totalResponseTimeMs;
  double averageResponseTimeMs;
  DateTime lastAccessTime;
  List<LogEntry> recentLogs;

  RequestStats({
    this.totalRequests = 0,
    this.successfulRequests = 0,
    this.failedRequests = 0,
    this.totalResponseTimeMs = 0,
    this.averageResponseTimeMs = 0,
    required this.lastAccessTime,
    List<LogEntry>? recentLogs,  // Make this parameter optional
  }) : recentLogs = recentLogs ?? []; // Initialize as empty mutable list if null

  Map<String, dynamic> toJson() => {
    'totalRequests': totalRequests,
    'successfulRequests': successfulRequests,
    'failedRequests': failedRequests,
    'totalResponseTimeMs': totalResponseTimeMs,
    'averageResponseTimeMs': averageResponseTimeMs,
    'lastAccessTime': lastAccessTime.toIso8601String(),
    'recentLogs': recentLogs.map((log) => log.toJson()).toList(),
  };

  factory RequestStats.fromJson(Map<String, dynamic> json) {
    return RequestStats(
      totalRequests: json['totalRequests'] ?? 0,
      successfulRequests: json['successfulRequests'] ?? 0,
      failedRequests: json['failedRequests'] ?? 0,
      totalResponseTimeMs: json['totalResponseTimeMs'] ?? 0,
      averageResponseTimeMs: json['averageResponseTimeMs'] ?? 0,
      lastAccessTime: DateTime.parse(json['lastAccessTime']),
      recentLogs: ((json['recentLogs'] as List?) ?? [])
          .map((log) => LogEntry.fromJson(log as Map<String, dynamic>))
          .toList(), // Create a new mutable list
    );
  }

  void updateStats(LogEntry newLog) {
    totalRequests++;
    if (newLog.error == null) {
      successfulRequests++;
    } else {
      failedRequests++;
    }
    
    totalResponseTimeMs += newLog.responseTimeMs;
    averageResponseTimeMs = totalResponseTimeMs / totalRequests;
    lastAccessTime = newLog.timestamp;
    
    // Create a new list if recentLogs is null
    if (recentLogs.length >= 10) {
      recentLogs.removeLast();
    }
    recentLogs.insert(0, newLog);
  }
}


class LogEntry {
  final Map<String, dynamic> requestData;
  final Map<String, dynamic>? responseData;
  final Map<String, dynamic> headers;
  final Map<String, dynamic> queryParameters;
  final int statusCode;
  final int responseTimeMs;
  final DateTime timestamp;
  final String? error;

  LogEntry({
    required this.requestData,
    this.responseData,
    required this.headers,
    required this.queryParameters,
    required this.statusCode,
    required this.responseTimeMs,
    required this.timestamp,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'requestData': requestData,
    'responseData': responseData,
    'headers': headers,
    'queryParameters': queryParameters,
    'statusCode': statusCode,
    'responseTimeMs': responseTimeMs,
    'timestamp': timestamp.toIso8601String(),
    'error': error,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      requestData: json['requestData'] ?? {},
      responseData: json['responseData'],
      headers: json['headers'] ?? {},
      queryParameters: json['queryParameters'] ?? {},
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

  String _sanitizePath(String path) {
    return path.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }

  Future<void> _updateStats(String path, LogEntry entry) async {
    try {
      final sanitizedPath = _sanitizePath(path);
      final statsDoc = await _db.collection('endpoint_stats').doc(sanitizedPath).get();
      
      RequestStats stats;
      if (statsDoc != null) {
        stats = RequestStats.fromJson(statsDoc as Map<String, dynamic>);
      } else {
        stats = RequestStats(
          lastAccessTime: entry.timestamp,
          recentLogs: [], // Initialize with empty mutable list
        );
      }
      
      stats.updateStats(entry);
      await _db.collection('endpoint_stats').doc(sanitizedPath).set(stats.toJson());
    } catch (e) {
      print('Failed to update stats: $e');
      print('Error stack trace: ${e is Error ? e.stackTrace : ''}');
    }
  }


  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final timestamp = DateTime.now();
    _requestTimes[options.path] = timestamp;

    print('🌐 REQUEST[${options.method}] => PATH: ${options.path}');
    
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final endTime = DateTime.now();
    final startTime = _requestTimes[response.requestOptions.path];
    final responseTimeMs = startTime != null 
        ? endTime.difference(startTime).inMilliseconds 
        : -1;

    final entry = LogEntry(
      requestData: response.requestOptions.data ?? {},
      //responseData: response.data,
      headers: response.requestOptions.headers,
      queryParameters: response.requestOptions.queryParameters,
      statusCode: response.statusCode ?? -1,
      responseTimeMs: responseTimeMs,
      timestamp: endTime,
    );

    _updateStats(response.requestOptions.path, entry);
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

    final entry = LogEntry(
      requestData: err.requestOptions.data ?? {},
      headers: err.requestOptions.headers,
      queryParameters: err.requestOptions.queryParameters,
      statusCode: err.response?.statusCode ?? -1,
      responseTimeMs: responseTimeMs,
      timestamp: endTime,
      error: err.message,
    );

    _updateStats(err.requestOptions.path, entry);
    _requestTimes.remove(err.requestOptions.path);
    
    handler.next(err);
  }

  Future<RequestStats?> getEndpointStats(String path) async {
    try {
      final sanitizedPath = _sanitizePath(path);
      final stats = await _db.collection('endpoint_stats').doc(sanitizedPath).get();
      return stats != null ? RequestStats.fromJson(stats) : null;
    } catch (e) {
      print('Failed to get endpoint stats: $e');
      return null;
    }
  }

  Future<void> clearOldEndpointStats({Duration? olderThan}) async {
    try {
      final stats = await _db.collection('endpoint_stats').get();
      if (stats == null) return;

      final cutoffDate = DateTime.now().subtract(olderThan ?? const Duration(days: 7));

      for (var entry in stats.entries) {
        final stat = RequestStats.fromJson(entry.value);
        if (stat.lastAccessTime.isBefore(cutoffDate)) {
          await _db.collection('endpoint_stats').doc(entry.key).delete();
        }
      }
    } catch (e) {
      print('Failed to clear old stats: $e');
    }
  }
}