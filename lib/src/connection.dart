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
    this.timeout,
    this.connectionState,
    this.onConnectionEstablish,
    this.onPong,
    this.onError,
    this.showLog = false,
  }) {
    bind('pusher:connection_established', _connectHandler);
    bind('pusher:pong', _pongHandler);
    bind('pusher:error', _pusherErrorHandler);
  }

  final String url;
  final Duration pingInterval;
  final Duration reconnectInterval;
  final Duration? timeout;
  final bool showLog;
  final EventHandler eventHandler;
  final Function(ConnState state)? connectionState;
  final Function(dynamic data)? onConnectionEstablish;
  final Function(dynamic data)? onPong;
  final Function(dynamic data)? onError;

  final Map<String, Function(dynamic event)> _eventCallbacks = {};
  WebSocket? _socket;
  Timer? _pongTimer;
  Timer? _connTimer;
  String? socketId;

  void _connectHandler(data) {
    if (showLog) log('Established first connection: $data', name: _kLogName);

    final json = jsonDecode(data);
    socketId = json['socket_id'];

    _updateState(ConnState.connected);
    if (onConnectionEstablish != null) onConnectionEstablish!(data);
  }

  void _pongHandler(data) {
    if (showLog) log('Pong received', name: _kLogName);
    if (onPong != null) onPong!(data);
  }

  void _pusherErrorHandler(data) {
    if (onError != null) onError!(data);
    try {
      if (data is Map && data.containsKey('code')) {
        final code = data['code'];
        if (code != null && code >= 4200 && code < 4300) {
          if (showLog) log('Trying to reconnect after error $code', name: _kLogName);
          reconnect();
        } else {
          if (showLog) log('Received pusher:error: $data', name: _kLogName);
        }
      } else {
        if (showLog) log('Received pusher:error without code: $data', name: _kLogName);
      }
    } catch (e, s) {
      final message = "Could not handle connection error";
      if (showLog) log(message, error: e, stackTrace: s, name: _kLogName);
      throw Exception(message);
    }
  }

  void bind(String eventName, Function(dynamic event) callback) {
    _eventCallbacks[eventName] = callback;
  }

  void reconnect() {
    if (showLog) log('reconnecting', name: _kLogName);
    _pongTimer?.cancel();
    _socket?.close();
    _socket = null;
    connect();
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
      if (timeout == null) {
        _socket = await WebSocket.connect(url);
      } else {
        _socket = await WebSocket.connect(url).timeout(timeout!, onTimeout: () {
          final seconds = timeout!.inSeconds;
          final message = 'Connection timeout : [$seconds] seconds';
          if (showLog) log(message, name: _kLogName);
          throw Exception(message);
        });
      }
      _socket?.listen(onMessage);
      _resetCheckPong();
    } catch (e, _) {
      final message = "Connection error : \n$e";
      if (showLog) log(message, name: _kLogName);
      throw Exception(message);
    }
    _checkConnection();
  }

  void _checkConnection() async {
    // Check first
    if (_socket == null) {
      // Delayed
      await Future.delayed(reconnectInterval);
      if (showLog) log('Internet connection is not established', name: _kLogName);
      reconnect();
      return;
    }

    _connTimer?.cancel();
    _connTimer = Timer.periodic(Duration(seconds: 1), (_) async {
      if (_socket?.closeCode != null) {
        if (showLog) log('Connection closed with code [${_socket?.closeCode}]', name: _kLogName);
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
      final message = "Unable to handle onMessage";
      if (showLog) log(message, error: e, stackTrace: s, name: _kLogName);
      throw Exception(message);
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
      final message = "Unable to send event $eventName to channel $channelName";
      if (showLog) log(message, error: e, stackTrace: s, name: _kLogName);
      throw Exception(message);
    }
  }

  void sendPing() {
    sendEvent('pusher:ping', {'data': ''});
    if (showLog) log('Ping sent', name: _kLogName);
  }

  void _updateState(ConnState state) {
    if (showLog) log('Connection state : ${state.name}', name: _kLogName);
    if (connectionState != null) connectionState!(state);
  }
}
