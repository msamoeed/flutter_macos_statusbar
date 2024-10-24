// curl_dio_converter.dart
import 'package:dio/dio.dart';
import 'dart:convert';

import 'package:flutter_statusbar_app/logging/logging_interceptor.dart';

class CurlDioConverter {
  static final Dio _dio = Dio()
    ..interceptors.addAll([
      LoggingInterceptor(),
      ErrorInterceptor(),
      RequestInterceptor(),
    ]);

  static Future<Response> executeCurl(String curlCommand) async {
    final RequestDetails details = parseCurlCommand(curlCommand);
    
    try {
      return await _dio.request(
        details.url,
        data: details.body,
        queryParameters: details.queryParams,
        options: Options(
          method: details.method,
          headers: details.headers,
          contentType: details.headers['Content-Type'],
          followRedirects: true,
          validateStatus: (status) => true, // Allow all status codes
        ),
      );
    } on DioException catch (e) {
      throw DioException(
        requestOptions: e.requestOptions,
        error: 'Failed to execute request: ${e.message}',
        type: e.type,
        response: e.response,
      );
    }
  }
  

  static RequestDetails parseCurlCommand(String curlCommand) {
    final details = RequestDetails();
    final List<String> parts = _splitCommand(curlCommand);
    
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i].trim();
      
      if (part.startsWith('curl')) continue;
      
      // Handle method
      if (part == '-X' && i + 1 < parts.length) {
        details.method = parts[++i];
        continue;
      }
      
      // Handle URL and query parameters
      if (part.startsWith('http://') || part.startsWith('https://')) {
        final urlString = part.replaceAll('"', '').replaceAll("'", '');
        final uri = Uri.parse(urlString);
        details.url = '${uri.scheme}://${uri.host}${uri.path}';
        details.queryParams.addAll(uri.queryParameters);
        continue;
      }
      
      // Handle headers
      if ((part == '-H' || part == '--header') && i + 1 < parts.length) {
        final header = parts[++i].replaceAll('"', '').replaceAll("'", '');
        final headerParts = header.split(':');
        if (headerParts.length == 2) {
          details.headers[headerParts[0].trim()] = headerParts[1].trim();
        }
        continue;
      }
      
      // Handle data
      if ((part == '-d' || part == '--data' || part == '--data-raw') && i + 1 < parts.length) {
        String data = parts[++i].replaceAll('"', '').replaceAll("'", '');
        
        // Check if data is URL-encoded
        if (data.contains('=') && !data.contains('{')) {
          final params = Uri.splitQueryString(data);
          if (details.method == 'GET') {
            details.queryParams.addAll(params);
          } else {
            details.formData.addAll(params);
            if (!details.headers.containsKey('Content-Type')) {
              details.headers['Content-Type'] = 'application/x-www-form-urlencoded';
            }
          }
        } else {
          // Try to parse as JSON
          try {
            final jsonObj = jsonDecode(data);
            details.body = jsonObj; // Dio handles JSON conversion
            if (!details.headers.containsKey('Content-Type')) {
              details.headers['Content-Type'] = 'application/json';
            }
          } catch (_) {
            details.body = data;
          }
        }
      }
    }
    
    if (details.url.isEmpty) {
      throw FormatException('No URL found in cURL command');
    }
    
    return details;
  }

  static List<String> _splitCommand(String command) {
    final List<String> parts = [];
    bool inQuotes = false;
    String currentQuote = '';
    String currentPart = '';
    
    for (int i = 0; i < command.length; i++) {
      final char = command[i];
      
      if ((char == '"' || char == "'") && (i == 0 || command[i - 1] != '\\')) {
        if (!inQuotes) {
          inQuotes = true;
          currentQuote = char;
        } else if (char == currentQuote) {
          inQuotes = false;
        } else {
          currentPart += char;
        }
      } else if (char.trim().isEmpty && !inQuotes) {
        if (currentPart.isNotEmpty) {
          parts.add(currentPart);
          currentPart = '';
        }
      } else {
        currentPart += char;
      }
    }
    
    if (currentPart.isNotEmpty) {
      parts.add(currentPart);
    }
    
    return parts;
  }
}

class RequestDetails {
  String method = 'GET';
  String url = '';
  Map<String, String> headers = {};
  dynamic body;
  Map<String, dynamic> queryParams = {};
  Map<String, String> formData = {};
}

// Interceptors

class ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        err = DioException(
          requestOptions: err.requestOptions,
          error: 'Connection timed out. Please check your internet connection.',
          type: err.type,
        );
        break;
      case DioExceptionType.badResponse:
        err = _handleBadResponse(err);
        break;
      case DioExceptionType.unknown:
        if (err.error.toString().contains('SocketException')) {
          err = DioException(
            requestOptions: err.requestOptions,
            error: 'No internet connection',
            type: err.type,
          );
        }
        break;
      default:
        break;
    }
    handler.next(err);
  }

  DioException _handleBadResponse(DioException err) {
    String message;
    switch (err.response?.statusCode) {
      case 400:
        message = 'Bad request';
        break;
      case 401:
        message = 'Unauthorized';
        break;
      case 403:
        message = 'Forbidden';
        break;
      case 404:
        message = 'Resource not found';
        break;
      case 500:
        message = 'Internal server error';
        break;
      default:
        message = 'Something went wrong';
    }
    return DioException(
      requestOptions: err.requestOptions,
      error: message,
      type: err.type,
      response: err.response,
    );
  }
}

class RequestInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // Add common headers
    // options.headers['Accept'] = 'application/json';
    // options.headers['User-Agent'] = 'Dio-cURL-Client/1.0.0';
    
    // Set default timeout
    options.connectTimeout = const Duration(seconds: 5);
    options.receiveTimeout = const Duration(seconds: 3);
    
    handler.next(options);
  }
}

// Example usage
void main() async {
  // Test cases
  final testCases = [
    // GET request with query parameters
   
    '''
curl --location 'https://www.google.com'
'''
    
 
  ];

  for (final curl in testCases) {
    try {
      final response = await CurlDioConverter.executeCurl(curl);
      
      print('Status: ${response.statusCode}');
      print('Data: ${response.data}');
    } catch (e) {
      print('Error: $e');
    }
  }
}