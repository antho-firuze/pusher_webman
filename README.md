# Pusher Webman Client for webman/push

`pusher_webman` is a not official pusher client for webman/push.

## Usage

A simple usage example:

```dart
import 'package:pusher_webman/pusher_webman.dart';

main() {
  final pusher = Pusher(
      url: 'ws://localhost:3131',
      key: "APP-KEY",
      auth: PusherAuth('http://localhost/plugin/webman/push/auth'),
    );
  pusher.connect();

  final channel = pusher.subscribe('channel');
  channel.bind('event', (event) {
    print('event: $event');
  });
}
```

## Features and bugs

Please file feature requests and bugs at the [issue tracker][tracker].

[tracker]: https://github.com/antho-firuze/pusher_webman/issues
