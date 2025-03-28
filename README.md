`pusher_webman` is a not official pusher client for webman/push.

This client is work in progress.

## Usage

A simple usage example:

```dart
import 'package:pusher_webman/pusher_webman.dart';

main() {
  final pusher = Pusher(
      url: 'ws://localhost:3131',
      key: "ac824d4958a5fe8a9553b90c28560f91",
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
