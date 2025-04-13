part of 'transports.dart';

/// Enum representing the transport types.
enum RealtimeTransportType {
  /// WebRTC transport type
  webrtc,

  /// WebSocket transport type
  websocket,
}

/// Enum representing the connection state of the transport.
enum RealtimeConnectionState {
  /// Transport is connecting
  connecting,

  /// Transport is connected
  connected,

  /// Transport is disconnected
  disconnected,

  /// Transport data channel is opened
  dataChannelOpened,
}

/// An abstract base class representing a RealtimeTransport.
/// Subclasses must implement:
/// * isConnected
/// * connect
/// * disconnect
/// * send
abstract class RealtimeTransport extends RealtimeEventHandler {
  static final _logger = Logger('openai_realtime_dart.transport');

  /// Create a new [RealtimeTransport] instance.
  ///
  /// [transportType] the [RealtimeTransportType] to create.
  /// [url] the URL of the transport.
  /// [apiKey] the API key to use for the transport.
  /// [dangerouslyAllowAPIKeyInBrowser] allow the API key to be used in the browser.
  /// [debug] enable debug logging.
  factory RealtimeTransport({
    required RealtimeTransportType transportType,
    String? url,
    String? apiKey,
    bool dangerouslyAllowAPIKeyInBrowser = false,
    bool debug = false,
  }) {
    switch (transportType) {
      case RealtimeTransportType.webrtc:
        return RealtimeTransportWebRTC._(
          url: url,
          apiKey: apiKey,
          dangerouslyAllowAPIKeyInBrowser: dangerouslyAllowAPIKeyInBrowser,
          debug: debug,
        );
      case RealtimeTransportType.websocket:
        return RealtimeTransportWebSocket._(
          url: url,
          apiKey: apiKey,
          dangerouslyAllowAPIKeyInBrowser: dangerouslyAllowAPIKeyInBrowser,
          debug: debug,
        );
    }
  }

  /// Get the transport type
  RealtimeTransportType get transportType => throw UnimplementedError();

  /// Get the default URL
  String get defaultUrl => throw UnimplementedError();

  /// Log messages when debug is enabled
  void _log(Level logLevel, String message) {
    if (debug) {
      _logger.log(logLevel, message);
    }
  }

  /// The URL of the transport
  late final String url;

  /// The API key to use for the transport
  final String? apiKey;

  /// Enable debug logging
  final bool debug;

  RealtimeTransport._({
    required String? url,
    required this.apiKey,
    required bool dangerouslyAllowAPIKeyInBrowser,
    required this.debug,
  }) : super() {
    this.url = url ?? defaultUrl;
    if (kIsWeb && apiKey != null) {
      if (!dangerouslyAllowAPIKeyInBrowser) {
        throw Exception(
          'Cannot provide API key in the browser without '
          '"dangerouslyAllowAPIKeyInBrowser" set to true',
        );
      }
    }
  }

  /// Dispose of the transport
  Future<void> dispose() async {
    await _connectionStateController.close();
    await _errorController.close();
    await _binaryMessageController.close();
    await _textMessageController.close();
  }

  RealtimeConnectionState _connectionState =
      RealtimeConnectionState.disconnected;

  final _connectionStateController =
      StreamController<RealtimeConnectionState>.broadcast();
  final _errorController = StreamController<Exception>.broadcast();
  final _binaryMessageController = StreamController<Uint8List>.broadcast();
  final _textMessageController = StreamController<String>.broadcast();

  /// Stream of transport state events
  Stream<RealtimeConnectionState> get onConnectionState =>
      _connectionStateController.stream;

  /// Stream of transport errors
  Stream<Exception> get onError => _errorController.stream;

  /// Stream of binary messages
  Stream<Uint8List> get onBinaryMessage => _binaryMessageController.stream;

  /// Stream of text messages
  Stream<String> get onTextMessage => _textMessageController.stream;

  /// Notify of connection state
  void notifyConnectionState(RealtimeConnectionState state) {
    _connectionState = state;
    //_log(['notifyConnectionState: _connectionState=$state']);
    _connectionStateController.add(state);
  }

  /// Notify of error
  void notifyError(Exception error) {
    _errorController.add(error);
  }

  /// Handle binary message (not really used)
  void notifyBinaryMessage(Uint8List data) {
    _binaryMessageController.add(data);
  }

  /// Handle text message
  void notifyTextMessage(String message) {
    _textMessageController.add(message);
  }

  /// Check if the transport is disconnected
  bool get isDisconnected =>
      _connectionState == RealtimeConnectionState.disconnected;

  /// Check if the transport is connecting or connected (ie: not disconnected)
  bool get isConnectingOrConnected => !isDisconnected;

  /// Check if the transport data channel is opened
  bool get isDataChannelOpened =>
      _connectionState == RealtimeConnectionState.dataChannelOpened;

  /// Connect to the transport
  Future<bool> connect({
    final RealtimeModel model = RealtimeUtils.defaultModel,
    final SessionConfig? sessionConfig,
  }) async {
    if (apiKey == null && url == defaultUrl) {
      _log(
        Level.WARNING,
        'Warning: No apiKey provided for connection to "$url"',
      );
    }
    if (isConnectingOrConnected) {
      throw Exception('Already connected');
    }
    if (kIsWeb && apiKey != null) {
      _log(
        Level.WARNING,
        'Warning: Connecting using API key in the browser, this is not recommended',
      );
    }
    return true;
  }

  /// Disconnect from the transport
  Future<void> disconnect() async {
    notifyConnectionState(RealtimeConnectionState.disconnected);
  }

  /// Send data through the transport
  Future<bool> send(dynamic data) async {
    return isDataChannelOpened;
  }
}
