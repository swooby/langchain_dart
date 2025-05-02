part of 'transports.dart';

/// A WebSocket transport for the Realtime API.
class RealtimeTransportWebSocket extends RealtimeTransport {
  @override
  RealtimeTransportType get transportType => RealtimeTransportType.websocket;

  @override
  String get defaultUrl => 'wss://api.openai.com/v1/realtime';

  RealtimeTransportWebSocket._({
    required super.url,
    required super.apiKey,
    required super.dangerouslyAllowAPIKeyInBrowser,
    required super.debug,
  }) : super._();

  WebSocketChannel? _ws;

  /// Connects to Realtime API Server.
  ///
  /// [model] specifies which model to use. You can find the list of available
  /// models [here](https://platform.openai.com/docs/models).
  ///
  /// [sessionConfig] ignored by websocket transport.
  @override
  Future<bool> connect({
    final RealtimeModel model = RealtimeUtils.defaultModel,
    final SessionConfig? sessionConfig,
    final Future<dynamic> Function()? getMicrophoneCallback,
  }) async {
    final result = await super.connect(model: model);
    if (!result) return result;
    _log(Level.INFO, 'connect(model="$model", sessionConfig=$sessionConfig)');
    final uri = Uri.parse('$url?model=${model.value}');
    try {
      _ws = connectWebSocket(uri, apiKey);

      // Wait for the connection to be established
      await _ws!.ready;

      _log(Level.FINE, 'connect: Connected to "$uri"');
      notifyConnectionState(RealtimeConnectionState.connected);

      _ws!.stream.listen(
        (data) {
          notifyTextMessage(data.toString());
        },
        onError: (dynamic error) async {
          _log(Level.SEVERE, 'websocket: Error; Disconnecting from "$uri"');
          notifyError(error);
          await disconnect();
        },
        onDone: () async {
          _log(Level.FINER, 'websocket: Disconnected from "$uri"');
          await disconnect();
        },
      );

      _log(Level.FINER, 'connect: Opened data channel to "$uri"');
      notifyConnectionState(RealtimeConnectionState.dataChannelOpened);

      return true;
    } catch (e) {
      _log(Level.SEVERE, 'connect: Could not connect to "$uri"; e=$e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    _log(Level.INFO, 'disconnect()');
    if (_ws != null) {
      await _ws!.sink.close(status.normalClosure);
      _ws = null;
    }
    await super.disconnect();
  }

  @override
  Future<bool> send(dynamic data) async {
    if (await super.send(data)) {
      _ws!.sink.add(json.encode(data));
      return true;
    } else {
      return false;
    }
  }
}
