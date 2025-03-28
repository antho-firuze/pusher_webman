import 'dart:convert';
import 'dart:developer';

import 'package:http/http.dart' as http show post;
import 'package:pusher_webman/pusher_webman.dart';

typedef PusherGlobalCallback = void Function(String channelName, String eventName, dynamic data);

class Pusher {
  final String url;
  final String cluster;
  final String client;
  final String version;
  final String key;
  final int protocol = 6;
  final Connection? connection;
  final Duration pingInterval;
  final Duration timeout;
  final PusherAuth? auth;
  final Function(ConnState state)? connectionState;

  Pusher({
    required this.key,
    this.auth,
    this.url = 'ws://pusher.com:443',
    this.cluster = 'eu',
    this.client = 'pusher.dart',
    this.version = '0.6.0',
    this.connection,
    this.pingInterval = const Duration(seconds: 30),
    this.timeout = const Duration(seconds: 10),
    this.connectionState,
  }) {
    _connection = connection ??
        Connection(
          url: "$url/app/$key?client=$client&version=$version&protocol=$protocol",
          eventHandler: connectionHandler,
          onConnectionEstablish: _onConnectionEstablish,
          pingInterval: pingInterval,
          timeout: timeout,
          connectionState: connectionState,
        );
  }

  late Connection _connection;
  PusherGlobalCallback? globalCallback;
  final Map<String, Channel> channels = {};

  Connection? get getConnection => _connection;

  void connect() => _connection.connect();

  void disconnect() => _connection.disconnect();

  void _onConnectionEstablish() {
    for (var channel in channels.keys) {
      _subscribe(channel);
    }
  }

  Channel subscribe(String channelName) {
    if (channels.containsKey(channelName)) {
      final channel = channels[channelName];
      return channel!;
    }

    final channel = Channel(name: channelName);
    channels[channelName] = channel;
    return channel;
  }

  void _subscribe(String channelName) async {
    if (channelName.startsWith('private-encrypted-')) {
      _privateEncryptedChannel(_connection, channelName);
    } else if (channelName.startsWith('private-')) {
      _privateChannel(_connection, channelName);
    } else if (channelName.startsWith('presence-')) {
      _presenceChannel(_connection, channelName);
    } else {
      _publicChannel(_connection, channelName);
    }
  }

  void unsubscribe(String channelName) {
    if (channels.containsKey(channelName)) {
      final data = {'channel': channelName};
      channels.remove(channelName);
      _connection.sendEvent('pusher:unsubscribe', data);
    }
  }

  void connectionHandler(
    String eventName,
    String channelName,
    Map<String, dynamic> data,
  ) {
    channels[channelName]?.handleEvent(eventName, data);
    globalCallback?.call(channelName, eventName, data);
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

  void _privateEncryptedChannel(Connection conn, String channelName) {
    final data = {'channel': channelName};
    conn.sendEvent('pusher:subscribe', data);
  }

  void _privateChannel(Connection conn, String channelName) async {
    try {
      final payload = {
        "channel_name": channelName,
        "socket_id": conn.socketId,
      };
      final response = await http.post(
        Uri.parse(auth!.endpoint),
        body: payload,
        headers: auth!.headers,
      );

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json['auth'] != null) {
          final data = {
            "channel": channelName,
            "auth": json['auth'],
          };
          conn.sendEvent('pusher:subscribe', data);
        }
        return;
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
  //      "auth":"b054014693241bcd9c26:10e3b628cb78e8bc4d1f44d47c9294551b446ae6ec10ef113d3d7e84e99763e6",
  //      "channel_data":
  //      {
  //        "user_id":100,
  //        "user_info":{"name":"123"},
  //      },
  //      "channel":"presence-channel",
  //    },
  // }
  void _presenceChannel(Connection conn, String channelName) async {
    try {
      final payload = {
        "channel_name": channelName,
        "socket_id": conn.socketId,
      };
      payload['channel_data'] = jsonEncode({
        "user_id": 1,
        "user_info": {
          "name": "User Satu",
        },
      });
      final response = await http.post(
        Uri.parse(auth!.endpoint),
        body: payload,
        headers: auth!.headers,
      );

      // log('response.statusCode : ${response.statusCode}', name: 'PUSHER');
      // log('response.body : ${response.body}', name: 'PUSHER');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json['auth'] != null) {
          final data = {
            "channel": channelName,
            "auth": json['auth'],
          };
          data['channel_data'] = jsonEncode({
            "user_id": 1,
            "user_info": {
              "name": "User Satu",
            },
          });
          conn.sendEvent('pusher:subscribe', data);
        }
        return;
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
