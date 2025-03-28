import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

const _kLogName = 'PusherConnection';

typedef EventHandler = void Function(
  String eventName,
  String channelName,
  Map<String, dynamic> data,
);

enum ConnState { connected, disconnected, connecting }

class Connection {
  Connection({
    required this.url,
    required this.eventHandler,
    this.pingInterval = const Duration(seconds: 30),
    this.reconnectInterval = const Duration(seconds: 3),
    this.timeout = const Duration(seconds: 10),
    this.connectionState,
    this.onConnectionEstablish,
  }) {
    bind('pusher:connection_established', _connectHandler);
    bind('pusher:pong', _pongHandler);
    bind('pusher:error', _pusherErrorHandler);
  }

  final String url;
  final EventHandler eventHandler;
  final Duration pingInterval;
  final Duration reconnectInterval;
  final Duration timeout;
  final Function(ConnState state)? connectionState;
  final Function()? onConnectionEstablish;

  final Map<String, Function(dynamic event)> _eventCallbacks = {};
  WebSocket? _socket;
  Timer? _pongTimer;
  Timer? _connTimer;
  String? socketId;

  void _connectHandler(data) {
    log('Established first connection: $data', name: _kLogName);

    final json = jsonDecode(data);
    socketId = json['socket_id'];

    _updateState(ConnState.connected);
    if (onConnectionEstablish != null) onConnectionEstablish!();
  }

  void _pongHandler(data) {
    log('Pong received', name: _kLogName);
  }

  void reconnect() {
    log('reconnecting', name: _kLogName);
    _pongTimer?.cancel();
    _socket?.close();
    _socket = null;
    connect();
  }

  void _pusherErrorHandler(data) {
    try {
      if (data is Map && data.containsKey('code')) {
        final code = data['code'];
        if (code != null && code >= 4200 && code < 4300) {
          reconnect();
          log('Trying to reconnect after error $code', name: _kLogName);
        }
      } else {
        log('Received pusher:error without code: $data', name: _kLogName);
        _updateState(ConnState.disconnected);
      }
    } catch (e, s) {
      log('Could not handle connection error', error: e, stackTrace: s, name: _kLogName);
    }
  }

  void bind(String eventName, Function(dynamic event) callback) {
    _eventCallbacks[eventName] = callback;
  }

  void disconnect() {
    _pongTimer?.cancel();
    _connTimer?.cancel();
    _socket?.close();
    _updateState(ConnState.disconnected);
  }

  void connect() async {
    _updateState(ConnState.connecting);
    try {
      _socket = await WebSocket.connect(url).timeout(timeout, onTimeout: () {
        throw Exception('Connection timeout');
      });
      _socket?.listen(onMessage);
      _resetCheckPong();
    } catch (e, _) {
      log('Connection error : \n$e', name: _kLogName);
    }
    _checkConnection();
  }

  void _checkConnection() async {
    // Check first
    if (_socket == null) {
      // Delayed
      await Future.delayed(reconnectInterval);
      log('Internet connection is not established', name: _kLogName);
      reconnect();
      return;
    }

    _connTimer?.cancel();
    _connTimer = Timer.periodic(Duration(seconds: 1), (_) async {
      if (_socket?.closeCode != null) {
        log('Connection closed with code [${_socket?.closeCode}]', name: _kLogName);
        _connTimer?.cancel();
        reconnect();
      }
    });
  }

  void _resetCheckPong() {
    _pongTimer?.cancel();
    _pongTimer = Timer.periodic(pingInterval, (_) => sendPing());
  }

  void onMessage(data) {
    try {
      final json = jsonDecode(data);
      if (json.containsKey('channel')) {
        eventHandler(json['event'], json['channel'], jsonDecode(json['data']));
      } else {
        _eventCallbacks[json['event']]?.call(json['data'] ?? {});
      }
    } catch (e, s) {
      log('Unable to handle onMessage', error: e, stackTrace: s, name: _kLogName);
    }
  }

  void sendEvent(
    String eventName,
    dynamic data, {
    String channelName = '',
  }) {
    try {
      final event = {
        'event': eventName,
        'data': data,
      };

      if (channelName.isNotEmpty) {
        event['channel'] = channelName;
      }

      _socket?.add(jsonEncode(event));
    } catch (e, s) {
      log('Unable to send event $eventName to channel $channelName', error: e, stackTrace: s, name: _kLogName);
    }
  }

  void sendPing() {
    sendEvent('pusher:ping', {'data': ''});
    log('Ping sent', name: _kLogName);
  }

  void _updateState(ConnState state) {
    log('Connection state : ${state.name}', name: _kLogName);
    if (connectionState != null) connectionState!(state);
  }
}
