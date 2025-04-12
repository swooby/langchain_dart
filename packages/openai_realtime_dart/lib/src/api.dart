// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';

import 'event_handler.dart';
import 'schema/generated/schema/schema.dart';
import 'transports.dart';
import 'utils.dart';

/// Thin wrapper over [WebSocket](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)
/// to handle the communication with OpenAI Realtime API.
///
/// Dispatches events as `server.{event_name}` and `client.{event_name}`,
/// respectively.
class RealtimeAPI extends RealtimeEventHandler {
  static final _logger = Logger('openai_realtime_dart.api');

  /// Create a new [RealtimeAPI] instance.
  RealtimeAPI({
    RealtimeTransportType? transportType,
    String? url,
    String? apiKey,
    bool dangerouslyAllowAPIKeyInBrowser = false,
    this.debug = false,
  }) {
    _transport = RealtimeTransport(
      transportType: transportType ?? RealtimeUtils.defaultTransport,
      url: url,
      apiKey: apiKey,
      dangerouslyAllowAPIKeyInBrowser: dangerouslyAllowAPIKeyInBrowser,
      debug: debug,
    );
    _transport.onTextMessage.listen((message) async {
      final messageObject = json.decode(message) as Map<String, dynamic>;
      await _receive(messageObject);
    });
  }

  late final RealtimeTransport _transport;

  /// The [RealtimeTransportType] used by the Realtime API.
  RealtimeTransportType get transportType => _transport.transportType;

  /// Whether to log debug messages.
  final bool debug;

  /// Tells us whether or not the Realtime API server is connecting or connected.
  bool get isConnectingOrConnected => _transport.isConnectingOrConnected;

  /// Tells us whether or not the Realtime API server data channel is opened.
  bool get isDataChannelOpened => _transport.isDataChannelOpened;

  StreamSubscription<dynamic>? _logSubscription;

  /// Log messages when debug is enabled
  void _log(Level logLevel, String message) {
    if (debug) {
      _logger.log(logLevel, message);
    }
  }

  /// Connects to Realtime API Server.
  ///
  /// `model` is specified separately from `sessionConfig` because the
  /// generated `SessionConfig` class does not have the `model` property.
  ///
  /// The OpenAI docs clearly state that `model` is part of `SessionConfig`:
  /// https://platform.openai.com/docs/api-reference/realtime-sessions/create
  /// > Can be configured with the same session parameters as the
  /// > `session.update` client event.
  /// https://platform.openai.com/docs/api-reference/realtime-client-events/session/update
  /// > However, note that once a session has been initialized with a particular
  /// > model, it can’t be changed to another model using session.update.
  ///
  /// [model] specifies which model to use. You can find the list of available
  /// models [here](https://platform.openai.com/docs/models).
  ///
  /// [sessionConfig] is a [SessionConfig] object that contains the configuration
  /// for the session; ignored by websocket transport.
  Future<bool> connect({
    final String model = RealtimeUtils.defaultModel,
    final SessionConfig? sessionConfig,
  }) {
    return _transport.connect(model: model, sessionConfig: sessionConfig);
  }

  /// Disconnects from Realtime API server.
  Future<void> disconnect() async {
    await _transport.disconnect();
    await _logSubscription?.cancel();
  }

  /// Receives an event from transport and dispatches as
  /// "[RealtimeEventType]" and "[RealtimeEventType.serverAll]" events.
  Future<void> _receive(Map<String, dynamic> eventData) async {
    final event = RealtimeEvent.fromJson(eventData);
    _logEvent(event, fromClient: false);
    await dispatch(event.type, event);
    await dispatch(RealtimeEventType.serverAll, event);
    await dispatch(RealtimeEventType.all, event);
  }

  /// Sends an event to Realtime API server and dispatches as
  /// "[RealtimeEventType]" and "[RealtimeEventType.clientAll]" events.
  Future<void> send(RealtimeEvent event) async {
    if (!isDataChannelOpened) {
      throw Exception('RealtimeAPI is not connected');
    }

    final finalEvent = event.copyWith(
      eventId: RealtimeUtils.generateId(),
    );

    _logEvent(finalEvent, fromClient: true);

    await dispatch(finalEvent.type, finalEvent);
    await dispatch(RealtimeEventType.clientAll, finalEvent);
    await dispatch(RealtimeEventType.all, finalEvent);

    await _transport.send(finalEvent.toJson());
  }

  void _logEvent(
    RealtimeEvent event, {
    required bool fromClient,
  }) {
    if (!debug) {
      return;
    }

    final eventJson = event.toJson();

    // Recursive function to replace "audio" property content
    void replaceAudioProperty(dynamic json) {
      if (json is Map<String, dynamic>) {
        json.forEach((key, value) {
          if (key == 'audio' ||
              (key == 'delta' && json['type'] == 'response.audio.delta')) {
            final base64EncodedAudio = value as String;
            json[key] =
                '${base64EncodedAudio.substring(0, 10)}...${base64EncodedAudio.substring(base64EncodedAudio.length - 10)}';
          } else {
            replaceAudioProperty(value);
          }
        });
      } else if (json is List) {
        for (var i = 0; i < json.length; i++) {
          replaceAudioProperty(json[i]);
        }
      }
    }

    // Replace "audio" property content in the event JSON
    replaceAudioProperty(eventJson);

    final eventString = jsonEncode(eventJson);
    _logger.info(
      '${fromClient ? 'sent' : 'received'}: ${event.type.name} $eventString',
    );
  }
}
