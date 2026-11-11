import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef MessageHandler = Future<void> Function(Map<String, dynamic>);

class MeshServer {
  final int port;
  final MessageHandler onEnvelope;
  ServerSocket? _server;

  MeshServer({required this.port, required this.onEnvelope});

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _server!.listen((client) {
      final buf = <int>[];
      client.listen(
        (data) => buf.addAll(data),
        onDone: () {
          try {
            if (buf.isNotEmpty) {
              final frame = _decodeFrame(buf);
              if (frame != null) onEnvelope(frame);
            }
          } catch (_) {}
          client.destroy();
        },
        onError: (_) => client.destroy(),
      );
    });
  }

  Map<String, dynamic>? _decodeFrame(List<int> data) {
    if (data.length < 4) return null;
    final len = (data[0] << 24) |
        (data[1] << 16) |
        (data[2] << 8) |
        data[3];
    if (data.length < 4 + len) return null;
    final jsonBytes = data.sublist(4, 4 + len);
    return jsonDecode(utf8.decode(jsonBytes)) as Map<String, dynamic>;
  }

  void stop() => _server?.close();
}
