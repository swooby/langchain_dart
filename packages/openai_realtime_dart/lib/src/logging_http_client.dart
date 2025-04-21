import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// Dart pseud-equivalent of okhttp's HttpLoggingInterceptor for logging
/// http.BaseClient requests and responses.
/// References:
/// https://github.com/leancodepl/flutter_corelibrary/blob/master/packages/leancode_debug_page/lib/src/core/logging_http_client.dart
/// https://github.com/square/okhttp/blob/master/okhttp-logging-interceptor/src/main/kotlin/okhttp3/logging/HttpLoggingInterceptor.kt
class LoggingHttpClient extends http.BaseClient {
  final http.Client _client;
  final Logger _logger;

  /// Constructor for LoggingHttpClient
  LoggingHttpClient({http.Client? client, Logger? logger})
      : _client = client ?? http.Client(),
        _logger = logger ?? Logger('LoggingHttpClient');

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final method = request.method;
    final url = request.url.toString();
    final String? requestBody;
    if (request is http.Request) {
      requestBody = request.body;
    } else {
      requestBody = null;
    }

    final length = requestBody?.length ?? 0;

    _logger.info('--> $method $url');
    request.headers.forEach((k, v) => _logger.info('$k: $v'));
    if (requestBody != null) {
      LineSplitter.split(requestBody).forEach(_logger.info);
    }
    _logger.info('--> END $method ($length-byte body)');

    final startTime = DateTime.now();
    final response = await _client.send(request);
    final endTime = DateTime.now();

    final responseBodyBytes = <int>[];

    final stream = response.stream.transform<List<int>>(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          responseBodyBytes.addAll(data);
          sink.add(data);
        },
        handleError: (error, stackTrace, sink) {
          _logger.info('<-- ERROR $error');
          sink.addError(error, stackTrace);
        },
        handleDone: (sink) {
          final responseBody = utf8.decode(responseBodyBytes);
          final length = responseBody.length;
          final elapsedMs = endTime.difference(startTime).inMilliseconds;
          _logger.info('<-- ${response.statusCode} $url (${elapsedMs}ms)');
          response.headers.entries
              .map((e) => _logger.info('${e.key}: ${e.value}'));
          LineSplitter.split(responseBody).forEach(_logger.info);
          _logger.info('<-- END HTTP ($length-byte body)');
          sink.close();
        },
      ),
    );

    return http.StreamedResponse(
      stream,
      response.statusCode,
      contentLength: response.contentLength,
      request: response.request,
      headers: response.headers,
      isRedirect: response.isRedirect,
      persistentConnection: response.persistentConnection,
      reasonPhrase: response.reasonPhrase,
    );
  }
}
