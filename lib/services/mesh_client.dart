import 'dart:convert';
import 'dart:io';

class MeshClient {
  static List<int> frame(Map<String, dynamic> envelope) {
    final bytes = utf8.encode(jsonEncode(envelope));
    final len = bytes.length;
    return [
      (len >> 24) & 0xff,
      (len >> 16) & 0xff,
      (len >> 8) & 0xff,
      len & 0xff,
      ...bytes,
    ];
  }

  static Future<bool> send(
    String ip,
    int port,
    Map<String, dynamic> envelope, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    Socket? socket;
    try {
      socket = await Socket.connect(ip, port, timeout: timeout);
      socket.add(frame(envelope));
      await socket.flush();
      return true;
    } catch (_) {
      return false;
    } finally {
      socket?.destroy();
    }
  }
}
