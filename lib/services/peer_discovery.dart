import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:network_info_plus/network_info_plus.dart';

class PeerDiscovery {
  static const int discoveryPort = 48899;
  static const String appTag = 'MESHCHAT_V1';

  final String myId;
  final String myName;
  final int myTcpPort;
  final void Function(Map<String, dynamic>) onPeer;

  RawDatagramSocket? _socket;
  Timer? _broadcastTimer;
  final NetworkInfo _info = NetworkInfo();

  PeerDiscovery({
    required this.myId,
    required this.myName,
    required this.myTcpPort,
    required this.onPeer,
  });

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4, discoveryPort,
        reuseAddress: true, reusePort: true);
    _socket!.broadcastEnabled = true;
    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final dg = _socket!.receive();
        if (dg == null) return;
        _handle(dg);
      }
    });
    _broadcastTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _broadcast());
  }

  void _handle(Datagram dg) {
    try {
      final msg = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (msg['tag'] != appTag) return;
      if (msg['id'] == myId) return;
      final ip = dg.address.address;
      onPeer({
        'id': msg['id'],
        'name': msg['name'],
        'ip': ip,
        'port': msg['port'],
      });
      _reply(ip);
    } catch (_) {}
  }

  void _reply(String ip) {
    final payload = jsonEncode({
      'tag': appTag,
      'id': myId,
      'name': myName,
      'port': myTcpPort,
    });
    _socket?.send(utf8.encode(payload), InternetAddress(ip), discoveryPort);
  }

  Future<void> _broadcast() async {
    final payload = jsonEncode({
      'tag': appTag,
      'id': myId,
      'name': myName,
      'port': myTcpPort,
    });
    final bytes = utf8.encode(payload);
    _socket?.send(bytes, InternetAddress('255.255.255.255'), discoveryPort);
    try {
      final wifiIp = await _info.getWIFIIP();
      if (wifiIp != null && wifiIp.isNotEmpty) {
        final parts = wifiIp.split('.');
        if (parts.length == 4) {
          final bcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
          _socket?.send(bytes, InternetAddress(bcast), discoveryPort);
        }
      }
    } catch (_) {}
  }

  void stop() {
    _broadcastTimer?.cancel();
    _socket?.close();
  }
}
