import 'package:mocktail/mocktail.dart';
import 'package:pusher_webman/pusher_webman.dart';
import 'package:test/test.dart';

class MockConnection extends Mock implements Connection {}

class MockChannel extends Mock implements Channel {}

void main() {
  group('Pusher', () {
    late Pusher pusher;

    setUp(() {
      pusher = Pusher(key: 'my-key', connection: MockConnection());
    });

    tearDown(() {
      reset(pusher.connection);
    });

    test('connect', () {
      when(
        () => pusher.connect(),
      ).thenAnswer(
        (_) async => Future.value(null),
      );

      pusher.connect();

      verify(
        () => pusher.connect(),
      ).called(1);
    });

    test('disconnect', () {
      pusher.disconnect();

      verify(
        () => pusher.disconnect(),
      ).called(1);
    });

    test('subscribe', () {
      final channel = pusher.subscribe('channel-name');

      expect(pusher.channels['channel-name'], channel);
      expect(channel.name, 'channel-name');

      verifyNever(
        () => pusher.getConnection?.sendEvent(
          'pusher:subscribe',
          {'channel': 'channel-name'},
        ),
      ).called(0);
    });

    test('unsubscribe', () {
      pusher.subscribe('channel-name');
      pusher.unsubscribe('channel-name');

      expect(pusher.channels.containsKey('channel-name'), false);
      verify(
        () => pusher.getConnection?.sendEvent(
          'pusher:unsubscribe',
          {'channel': 'channel-name'},
        ),
      ).called(1);
    });

    // test('connectionHandler', () {
    //   final mockChannel = MockChannel();
    //   pusher.channels['channel-name'] = mockChannel;
    //   pusher.connectionHandler('event-name', 'channel-name', {'key': 'value'});

    //   verify(
    //     () => mockChannel.handleEvent(
    //       'event-name',
    //       {'key': 'value'},
    //     ),
    //   ).called(1);
    // });

    test('bindGlobal', () {
      var value = '';
      pusher.bindGlobal((channelName, eventName, data) {
        value =
            'event $eventName from $channelName with data $data has been executed';
      });
      // pusher.connectionHandler('event-name', 'channel-name', {'key': 'value'});
      expect(
        value,
        'event event-name from channel-name with data {key: value} has been executed',
      );
    });

    test('unbindGlobal', () {
      pusher.bindGlobal((_, __, ___) {});
      expect(pusher.globalCallback == null, false);

      pusher.unbindGlobal();
      expect(pusher.globalCallback == null, true);
    });

    test('trigger', () {
      pusher.trigger(
        channelName: 'channel-name',
        eventName: 'event-name',
        data: {'key': 'value'},
      );

      verify(
        () => pusher.getConnection?.sendEvent(
          'client-event-name',
          {'key': 'value'},
          channelName: 'channel-name',
        ),
      ).called(1);
    });
  });
}
