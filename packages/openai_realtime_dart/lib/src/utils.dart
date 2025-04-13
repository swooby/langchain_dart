// ignore_for_file: public_member_api_docs, cascade_invocations
import 'dart:math';
import 'dart:typed_data';

import 'transports.dart';

/// From https://platform.openai.com/docs/models
enum RealtimeModel {
  gpt4oRealtimePreview('gpt-4o-realtime-preview'),
  gpt4oMiniRealtimePreview('gpt-4o-mini-realtime-preview');

  final String value;

  const RealtimeModel(this.value);
}

class RealtimeUtils {
  RealtimeUtils._();

  /// Default transport type for OpenAI Realtime API.
  static const RealtimeTransportType defaultTransport =
      RealtimeTransportType.websocket;

  /// Default model for OpenAI Realtime API.
  static const RealtimeModel defaultModel =
      RealtimeModel.gpt4oMiniRealtimePreview;

  static Uint8List mergeUint8Lists(Uint8List left, Uint8List right) {
    final result = Uint8List(left.length + right.length);
    result.setRange(0, left.length, left);
    result.setRange(left.length, result.length, right);
    return result;
  }

  static String generateId({String prefix = 'evt_', int length = 21}) {
    const chars = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
    final random = Random();
    final str = List.generate(
      length - prefix.length,
      (_) => chars[random.nextInt(chars.length)],
    ).join('');
    return '$prefix$str';
  }

  static bool isInformational(int requestCode) {
    return requestCode >= 100 && requestCode <= 199;
  }

  static bool isSuccessful(int requestCode) {
    return requestCode >= 200 && requestCode <= 299;
  }

  static bool isRedirection(int requestCode) {
    return requestCode >= 300 && requestCode <= 399;
  }

  static bool isClientError(int requestCode) {
    return requestCode >= 400 && requestCode <= 499;
  }

  static bool isServerError(int requestCode) {
    return requestCode >= 500 && requestCode <= 999;
  }
}
