part of 'transports.dart';

/// A WebRTC transport for the Realtime API.
/// References:
/// * https://github.com/fuwei007/OpenAIRealtimeAPIFlutterWebRTC/
/// * https://www.videosdk.live/blog/flutter-webrtc
///   * https://github.com/videosdk-live/videosdk-rtc-flutter-sdk-example/
class RealtimeTransportWebRTC extends RealtimeTransport {
  @override
  RealtimeTransportType get transportType => RealtimeTransportType.webrtc;

  @override
  String get defaultUrl => 'https://api.openai.com/v1/realtime';

  RealtimeTransportWebRTC._({
    required super.url,
    required super.apiKey,
    required super.dangerouslyAllowAPIKeyInBrowser,
    required super.debug,
  }) : super._();

  /// Standard http client
  static final _httpClient = http.Client();

  /// Logging http client
  static final _httpLoggingClient = LoggingHttpClient(
    client: _httpClient,
    logger: RealtimeTransport._logger,
  );

  /// Set to true to enable debug HTTP logging.
  /// NOTE/WARNING that enabling this **WILL** log the API key in the request.
  static const bool _debugHttp = true;

  final http.Client _client = _debugHttp ? _httpLoggingClient : _httpClient;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localStream;

  /// Connects to the Realtime API server.
  ///
  /// [model] specifies which model to use. You can find the list of available
  /// models [here](https://platform.openai.com/docs/models).
  ///
  /// [sessionConfig] is a [SessionConfig] object that contains the configuration
  /// for the session; ignored by websocket transport.
  @override
  Future<bool> connect({
    final RealtimeModel model = RealtimeUtils.defaultModel,
    final SessionConfig? sessionConfig,
    final Future<dynamic> Function()? getMicrophoneCallback,
  }) async {
    final result = await super.connect(model: model);
    if (!result) return result;
    _log(Level.INFO, 'connect(model="$model", sessionConfig=$sessionConfig)');
    final ephemeralApiToken = await _requestEphemeralApiToken(
      apiKey!,
      {
        'model': model.value,
        ...?sessionConfig?.toJson(),
      },
    );
    return _init(ephemeralApiToken, model, getMicrophoneCallback);
  }

  /// Initially from:
  /// https://platform.openai.com/docs/guides/realtime-webrtc#creating-an-ephemeral-token
  Future<String> _requestEphemeralApiToken(
    String apiKey,
    Map<String, dynamic> sessionConfig,
  ) async {
    final response = await _client.post(
      Uri.parse('$url/sessions'),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      },
      body: json.encode(sessionConfig),
    );
    final data = json.decode(response.body) as Map<String, dynamic>;
    final clientSecret = data['client_secret'] as Map<String, dynamic>;
    return clientSecret['value'] as String;
  }

  /// Initially from:
  /// https://platform.openai.com/docs/guides/realtime-webrtc#connection-details
  Future<bool> _init(
    String ephemeralApiToken,
    RealtimeModel model,
    Future<dynamic> Function()? getMicrophoneCallback,
  ) async {
    _log(Level.FINER, 'init(...)');
    try {
      final configuration = <String, dynamic>{
        // ICE/STUN is not needed to talk to *server* (only needed for peer-to-peer)
      };
      _peerConnection = await createPeerConnection(configuration);

      if (getMicrophoneCallback != null) {
        _localStream = await getMicrophoneCallback() as MediaStream;
        _localStream?.getTracks().forEach((track) {
          _peerConnection!.addTrack(track, _localStream!);
        });
      }

      final offerConstraints = <String, dynamic>{
        'mandatory': {
          'OfferToReceiveAudio': true,
          'OfferToReceiveVideo': false,
        },
      };

      final dataChannelInit = RTCDataChannelInit();
      _dataChannel = await _peerConnection!.createDataChannel(
        'oai-events',
        dataChannelInit,
      );

      _dataChannel!.onDataChannelState = (RTCDataChannelState state) async {
        switch (state) {
          case RTCDataChannelState.RTCDataChannelConnecting:
            _log(Level.FINE, '_dataChannel: Connecting');
          case RTCDataChannelState.RTCDataChannelOpen:
            _log(Level.FINE, '_dataChannel: Open');
            notifyConnectionState(RealtimeConnectionState.dataChannelOpened);
          case RTCDataChannelState.RTCDataChannelClosing:
            _log(Level.FINE, '_dataChannel: Closing');
          case RTCDataChannelState.RTCDataChannelClosed:
            _log(Level.FINE, '_dataChannel: Closed');
            await disconnect();
        }
      };

      _dataChannel!.onMessage = (RTCDataChannelMessage message) {
        if (message.isBinary) {
          // Not expected to be used
          notifyBinaryMessage(message.binary);
        } else {
          notifyTextMessage(message.text);
        }
      };

      final offer = await _peerConnection!.createOffer(offerConstraints);
      _log(Level.FINEST, 'init: Created offer "${offer.sdp}"');
      await _peerConnection!.setLocalDescription(offer);
      final answer = await _sendSdpToServer(model, ephemeralApiToken, offer);
      _log(Level.FINEST, 'init: Got answer "${answer.sdp}"');
      await _peerConnection!.setRemoteDescription(answer);

      _log(Level.INFO, 'init: Connected!');
      notifyConnectionState(RealtimeConnectionState.connected);

      return true;
    } catch (e) {
      _log(Level.SEVERE, 'init: error: $e');
      await disconnect();
      return false;
    }
  }

  Future<RTCSessionDescription> _sendSdpToServer(
    RealtimeModel model,
    String key,
    RTCSessionDescription offer,
  ) async {
    final offerSdp = offer.sdp;
    if (offerSdp == null || offerSdp.isEmpty) {
      throw Exception('offer.sdp is null and cannot be used');
    }

    // The following `utf8.encode(...)` line prevents:
    // {
    //     "error": {
    //         "message": "Unsupported content type. This API method only accepts 'application/sdp' requests, but you specified the header 'Content-Type: application/sdp; charset=utf-8'. Please try again with a supported content type.",
    //         "type": "invalid_request_error",
    //         "code": "unsupported_content_type",
    //         "param": ""
    //     }
    // }
    final body = utf8.encode(offerSdp);

    final response = await _client.post(
      // Example: https://api.openai.com/v1/realtime?model=gpt-4o-mini-realtime-preview
      Uri.parse('$url?model=${model.value}'),
      headers: {
        'Authorization': 'Bearer $key',
        'Content-Type': 'application/sdp',
      },
      body: body,
    );

    // TODO: Follow redirects, handle info/error...

    final responseStatusCode = response.statusCode;
    final responseBody = response.body;

    if (!RealtimeUtils.isSuccessful(responseStatusCode)) {
      _log(Level.SEVERE,
          '_sendSdpToServer: Failed to get remote SDP answer; statusCode=$responseStatusCode; body=$responseBody');
      throw Exception('Remote SDP negotiation failed');
    }

    final answerSdp = responseBody;
    if (answerSdp.isEmpty) {
      throw Exception('Received empty answer SDP');
    }
    return RTCSessionDescription(answerSdp, 'answer');
  }

  @override
  Future<void> disconnect() async {
    _log(Level.INFO, 'disconnect()');
    if (_dataChannel != null) {
      await _dataChannel!.close();
      _dataChannel = null;
    }
    if (_peerConnection != null) {
      await _peerConnection!.close();
      _peerConnection = null;
    }
    await super.disconnect();
  }

  @override
  Future<bool> send(dynamic data) async {
    if (await super.send(data)) {
      await _dataChannel?.send(RTCDataChannelMessage(json.encode(data)));
      return true;
    } else {
      return false;
    }
  }
}
