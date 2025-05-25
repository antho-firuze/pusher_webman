import 'dart:convert';
import 'dart:developer';

import 'package:dio/dio.dart';
import 'package:pusher_webman/pusher_webman.dart';

typedef PusherGlobalCallback = void Function(String channelName, String eventName, dynamic data);
const _kLogName = 'PusherWebman';

class Pusher {
  final String url;
  final String cluster;
  final String client;
  final String version;
  final String key;
  final int protocol = 6;
  final Connection? connection;
  final Duration pingInterval;
  final Duration? timeout;
  final PusherAuth? auth;
  final bool showLog;
  final Function(ConnState state)? connectionState;
  final Function(dynamic data)? onError;
  final Function(String channelName)? onSubscribed;
  final Function(String channelName)? onUnsubscribed;

  Pusher({
    required this.key,
    this.auth,
    this.url = 'ws://pusher.com:443',
    this.cluster = 'eu',
    this.client = 'pusher.dart',
    this.version = '0.6.0',
    this.connection,
    this.pingInterval = const Duration(seconds: 30),
    this.timeout,
    this.connectionState,
    this.onError,
    this.onSubscribed,
    this.onUnsubscribed,
    this.showLog = false,
  }) {
    _connection = connection ??
        Connection(
          url: "$url/app/$key?client=$client&version=$version&protocol=$protocol",
          eventHandler: _connectionHandler,
          onConnectionEstablish: _onConnectionEstablish,
          pingInterval: pingInterval,
          timeout: timeout,
          connectionState: connectionState,
          onError: onError,
          showLog: showLog,
        );
  }

  late Connection _connection;
  PusherGlobalCallback? globalCallback;
  final Map<String, Channel> channels = {};

  Connection? get getConnection => _connection;

  Future connect() async {
    try {
      await _connection.connect();
    } catch (e) {
      rethrow;
    }
  }

  void disconnect() => _connection.disconnect();

  void _onConnectionEstablish(data) {
    for (var channel in channels.values) {
      _subscribe(channel);
    }
  }

  Channel subscribe(String channelName, {String? userId, Object? userInfo}) {
    Channel? channel;

    if (channels.containsKey(channelName)) {
      channel = channels[channelName];
    } else {
      channel = Channel(name: channelName, userId: userId, userInfo: userInfo);
      channels[channelName] = channel;
    }

    if (channel?.register == false) {
      if (_connection.socketId != null) {
        _subscribe(channel!);
      }
    }

    return channel!;
  }

  void _subscribe(Channel channel) async {
    String channelName = channel.name;
    String? userId = channel.userId;
    Object? userInfo = channel.userInfo;

    if (channelName.startsWith('private-')) {
      _privateChannel(_connection, channelName);
    } else if (channelName.startsWith('presence-')) {
      if (userId != null && userId.isNotEmpty) {
        _presenceChannel(_connection, channelName, userId: userId, userInfo: userInfo);
      } else {
        final message = "Error: $channelName is required [userId]";
        if (showLog) log(message, name: _kLogName);
        throw Exception(message);
      }
    } else {
      _publicChannel(_connection, channelName);
    }
  }

  void unsubscribe(String channelName) {
    if (channels.containsKey(channelName)) {
      final data = {'channel': channelName};
      channels.remove(channelName);
      _connection.sendEvent('pusher:unsubscribe', data);
      if (onUnsubscribed != null) onUnsubscribed!(channelName);
    }
  }

  void _connectionHandler(String eventName, String channelName, Map<String, dynamic> data) {
    channels[channelName]?.handleEvent(eventName, data);
    globalCallback?.call(channelName, eventName, data);

    if (eventName == 'pusher_internal:subscription_succeeded') {
      if (showLog) log("[$channelName][subscription_succeeded] $data", name: _kLogName);
      channels[channelName]?.register = true;
      if (onSubscribed != null) onSubscribed!(channelName);
    } else if (eventName == 'pusher_internal:member_removed') {
      if (showLog) log("[$channelName][member_removed] $data", name: _kLogName);
    }
  }

  void bindGlobal(PusherGlobalCallback callback) {
    globalCallback = callback;
  }

  void unbindGlobal() {
    globalCallback = null;
  }

  void trigger({
    required String channelName,
    required String eventName,
    dynamic data,
  }) {
    _connection.sendEvent(
      // client events should have the 'client-' prefix'
      // refs: https://pusher.com/docs/channels/library_auth_reference/pusher-websockets-protocol/#triggering-channel-client-events
      'client-$eventName',
      data,
      channelName: channelName,
    );
  }

  void _privateChannel(Connection conn, String channelName) async {
    try {
      final payload = {
        "channel_name": channelName,
        "socket_id": conn.socketId,
      };
      final response = await Dio().post(
        Uri.parse(auth!.endpoint).toString(),
        data: payload,
        options: Options(headers: auth!.headers),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.data);

        if (json['auth'] != null) {
          final data = {
            "channel": channelName,
            "auth": json['auth'],
          };
          conn.sendEvent('pusher:subscribe', data);
          return;
        }
      }

      throw Exception('Unable to authenticate channel $channelName, status code: ${response.statusCode}');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  // {
  //    "event":"pusher:subscribe",
  //    "data":
  //    {
  //      "channel":"presence-channel",
  //      "auth":"b054014693241bcd9c26:10e3b628cb78e8bc4d1f44d47c9294551b446ae6ec10ef113d3d7e84e99763e6",
  //      "channel_data":
  //      {
  //        "user_id":100,
  //        "user_info":{"name":"123"}
  //      }
  //    },
  // }
  void _presenceChannel(Connection conn, String channelName, {required String userId, Object? userInfo}) async {
    try {
      Map<String, dynamic> payload = {
        "channel_name": channelName,
        "socket_id": conn.socketId ?? "",
      };
      payload['user_id'] = userId;
      payload['user_info'] = userInfo ?? {"name": ""};
      final response = await Dio().post(
        Uri.parse(auth!.endpoint).toString(),
        data: payload,
        options: Options(headers: auth!.headers),
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.data);

        if (json['auth'] != null) {
          final data = {
            "channel": channelName,
            "auth": json['auth'],
            "channel_data": json['channel_data'],
          };
          conn.sendEvent('pusher:subscribe', data);
          return;
        }
      }

      throw Exception('Unable to authenticate channel $channelName, status code: ${response.statusCode}');
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  void _publicChannel(Connection conn, String channelName) {
    final data = {'channel': channelName};
    conn.sendEvent('pusher:subscribe', data);
  }
}
