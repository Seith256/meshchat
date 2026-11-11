import 'dart:async';
import '../models/message.dart';
import '../models/user.dart';
import 'crypto_service.dart';
import 'db_service.dart';
import 'identity_service.dart';
import 'mesh_client.dart';

class RelayService {
  final Map<String, _Peer> peers = {};
  final Set<String> _seenMessageIds = {};
  Timer? _tick;

  void start() {
    _tick = Timer.periodic(
        const Duration(seconds: 10), (_) => _flushRelayQueue());
  }

  void stop() => _tick?.cancel();

  void updatePeer(String id, String name, String ip, int port,
      {String? publicKey}) {
    peers[id] = _Peer(id: id, name: name, ip: ip, port: port);
    final existing = DbService.getUser(id);
    DbService.saveUser(MeshUser(
      id: id,
      name: name,
      publicKey: publicKey ?? existing?.publicKey,
      lastSeen: DateTime.now().millisecondsSinceEpoch,
      lastIp: ip,
      lastPort: port,
    ));
  }

  Future<void> handleEnvelope(Map<String, dynamic> env) async {
    final type = env['type'];
    final msgId = env['mid'] as String?;
    if (msgId != null) {
      if (_seenMessageIds.contains(msgId)) return;
      _seenMessageIds.add(msgId);
      if (_seenMessageIds.length > 5000) _seenMessageIds.clear();
    }

    switch (type) {
      case 'MSG':
        await _onMessage(env);
        break;
      case 'ACK':
        await _onAck(env);
        break;
      case 'HELLO':
        await _onHello(env);
        break;
    }
  }

  Future<void> _onHello(Map<String, dynamic> env) async {
    final id = env['id'] as String?;
    if (id == null) return;
    final pub = env['pub'] as String?;
    if (pub != null) {
      final u = DbService.getUser(id);
      if (u != null) {
        u.publicKey = pub;
        DbService.saveUser(u);
      }
    }
  }

  Future<void> _onMessage(Map<String, dynamic> env) async {
    final myId = IdentityService.myId!;
    final to = env['to'] as String;
    final from = env['from'] as String;
    final mid = env['mid'] as String;
    final ttl = (env['ttl'] as int?) ?? 7;

    if (to == myId) {
      try {
        final cipher = env['cipher'] as String;
        final plain = await CryptoService.decrypt(
            cipher, IdentityService.myPrivateKey!);
        final msg = MeshMessage(
          id: mid,
          from: from,
          to: to,
          body: plain,
          createdAt: env['ts'] ?? DateTime.now().millisecondsSinceEpoch,
          status: 'delivered',
        );
        await DbService.saveMessage(msg);
        _sendAck(to: from, mid: mid, acker: myId);
      } catch (_) {}
      return;
    }

    if (ttl <= 1) return;
    final existing = DbService.getMessage(mid);
    if (existing != null && existing.status == 'delivered') return;

    final m = MeshMessage(
      id: mid,
      from: from,
      to: to,
      body: '',
      ciphertext: env['cipher'] as String?,
      createdAt: env['ts'] ?? DateTime.now().millisecondsSinceEpoch,
      ttl: ttl - 1,
      status: 'queued',
    );
    if (existing == null) await DbService.saveMessage(m);
    await DbService.enqueueRelay(m);
    _tryForward(m);
  }

  Future<void> _onAck(Map<String, dynamic> env) async {
    final mid = env['mid'] as String?;
    if (mid == null) return;
    final m = DbService.getMessage(mid);
    if (m != null) {
      m.status = 'delivered';
      await DbService.saveMessage(m);
    }
    await DbService.removeRelay(mid);
  }

  Future<void> _sendAck(
      {required String to, required String mid, required String acker}) async {
    final peer = peers[to];
    if (peer == null) return;
    await MeshClient.send(peer.ip, peer.port, {
      'type': 'ACK',
      'mid': mid,
      'from': acker,
    });
  }

  Future<void> sendMessage(MeshMessage msg, {required String toId}) async {
    msg.status = 'sent';
    await DbService.saveMessage(msg);

    final user = DbService.getUser(toId);
    if (user?.publicKey == null) {
      msg.status = 'queued';
      await DbService.saveMessage(msg);
      await DbService.enqueueRelay(msg);
      return;
    }

    final cipher =
        await CryptoService.encryptFor(msg.body, user!.publicKey!);
    final env = {
      'type': 'MSG',
      'mid': msg.id,
      'from': msg.from,
      'to': msg.to,
      'cipher': cipher,
      'ts': msg.createdAt,
      'ttl': 7,
    };

    final sent = await _flood(env);
    if (!sent) {
      msg.status = 'queued';
      await DbService.saveMessage(msg);
      await DbService.enqueueRelay(
          msg.copyWith(status: 'queued', ciphertext: cipher));
    }
  }

  Future<void> _tryForward(MeshMessage m) async {
    if (m.ciphertext == null) return;
    final env = {
      'type': 'MSG',
      'mid': m.id,
      'from': m.from,
      'to': m.to,
      'cipher': m.ciphertext,
      'ts': m.createdAt,
      'ttl': m.ttl,
    };
    final ok = await _flood(env);
    if (ok) await DbService.removeRelay(m.id);
  }

  Future<bool> _flood(Map<String, dynamic> env) async {
    var anySuccess = false;
    final target = env['to'] as String;
    final direct = peers[target];
    if (direct != null) {
      final ok = await MeshClient.send(direct.ip, direct.port, env);
      if (ok) return true;
    }
    for (final p in peers.values) {
      if (p.id == env['from']) continue;
      final ok = await MeshClient.send(p.ip, p.port, env);
      if (ok) anySuccess = true;
    }
    return anySuccess;
  }

  Future<void> _flushRelayQueue() async {
    for (final m in DbService.relayQueue()) {
      await _tryForward(m);
    }
  }

  Future<void> sendHello(String peerId) async {
    final p = peers[peerId];
    if (p == null) return;
    await MeshClient.send(p.ip, p.port, {
      'type': 'HELLO',
      'id': IdentityService.myId,
      'name': IdentityService.myName,
      'pub': IdentityService.myPublicKey,
    });
  }
}

class _Peer {
  final String id;
  final String name;
  final String ip;
  final int port;
  _Peer(
      {required this.id,
      required this.name,
      required this.ip,
      required this.port});
}
