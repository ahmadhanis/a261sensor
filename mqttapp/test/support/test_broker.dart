import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Minimal MQTT 3.1.1 peer for exercising the real client over loopback TCP.
/// Only implements the packet types used by these tests.
class TestBroker {
  TestBroker._(this.server, this.rejectLogin, this.rejectSubscription) {
    server.listen((socket) {
      sockets.add(socket);
      final buffer = <int>[];
      socket.listen((chunk) {
        buffer.addAll(chunk);
        while (buffer.length >= 2) {
          var length = 0;
          var multiplier = 1;
          var offset = 1;
          int digit;
          do {
            if (offset >= buffer.length) return;
            digit = buffer[offset++];
            length += (digit & 127) * multiplier;
            multiplier *= 128;
          } while ((digit & 128) != 0);
          if (buffer.length < offset + length) return;
          final header = buffer.first;
          final body = buffer.sublist(offset, offset + length);
          buffer.removeRange(0, offset + length);
          switch (header >> 4) {
            case 1: // CONNECT
              connectBody = body;
              socket.add([0x20, 2, 0, rejectLogin ? 5 : 0]);
            case 8: // SUBSCRIBE
              final topicLength = body[2] * 256 + body[3];
              subscription = utf8.decode(body.sublist(4, 4 + topicLength));
              socket.add([
                0x90,
                3,
                body[0],
                body[1],
                rejectSubscription ? 0x80 : 1,
              ]);
            case 3: // PUBLISH; echo as a new QoS 0 delivery
              lastPublishedHeader = header;
              _send(socket, 0x30, body);
            case 12: // PINGREQ
              socket.add([0xD0, 0]);
            case 14: // DISCONNECT
              socket.close();
          }
        }
      }, onError: (Object _) {});
    });
  }

  final ServerSocket server;
  final bool rejectLogin;
  final bool rejectSubscription;
  final sockets = <Socket>[];
  List<int>? connectBody;
  String? subscription;
  int? lastPublishedHeader;
  int get port => server.port;

  static Future<TestBroker> start({
    bool rejectLogin = false,
    bool rejectSubscription = false,
  }) async => TestBroker._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    rejectLogin,
    rejectSubscription,
  );

  void publish(String topic, String payload, {bool retained = false}) {
    final topicBytes = utf8.encode(topic);
    final body = [
      topicBytes.length >> 8,
      topicBytes.length & 255,
      ...topicBytes,
      ...utf8.encode(payload),
    ];
    for (final socket in sockets) {
      _send(socket, retained ? 0x31 : 0x30, body);
    }
  }

  void _send(Socket socket, int header, List<int> body) {
    var remaining = body.length;
    final lengthBytes = <int>[];
    do {
      var byte = remaining % 128;
      remaining ~/= 128;
      if (remaining > 0) byte |= 128;
      lengthBytes.add(byte);
    } while (remaining > 0);
    socket.add([header, ...lengthBytes, ...body]);
  }

  void dropConnections() {
    for (final socket in sockets) {
      socket.destroy();
    }
    sockets.clear();
  }

  Future<void> close() async {
    dropConnections();
    await server.close();
  }
}
