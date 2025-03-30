
import 'package:flutter/material.dart';

import 'pusher_client.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pusher Client Socket',
      theme: ThemeData(
        useMaterial3: true,
      ),
      // home: const WebSocketClient(),
      home: const PusherClient(),
    );
  }
}

