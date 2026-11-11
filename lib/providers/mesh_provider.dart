import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/crypto_service.dart';
import '../services/db_service.dart';
import '../services/identity_service.dart';
import '../services/mesh_server.dart';
import '../services/peer_discovery.dart';
import '../services/relay_service.dart';

class MeshProvider extends ChangeNotifier {
  bool loading = true;
  String? myId;
  String? myName;

  final RelayService _relay = RelayService();
  late MeshServer _server;
  PeerDiscovery? _discovery;
  int _myPort = 0;

  int get myPort => _myPort;

  Future<void> init() async {
    if (IdentityService.myPrivateKey == null) {
      final (priv, pub) = await CryptoService.generateKeypair();
      await IdentityService.saveKeys(priv, pub);
    }
    myId = IdentityService.myId;
    myName = IdentityService.myName;
    loading = false;
    notifyListeners();

    if (myId != null) await _bootNetwork();
  }

  Future<void> setup(String name) async {
    await IdentityService.create(name: name);
    myId = IdentityService.myId;
    myName = IdentityService.myName;
    notifyListeners();
    await _bootNetwork();
  }

  Future<void> _bootNetwork() async {
    _myPort = 40000 + Random().nextInt(10000);

    _server = MeshServer(
      port: _myPort,
      onEnvelope: (env) async {
        await _relay.handleEnvelope(env);
        notifyListeners();
      },
    );
    await _server.start();

    _discovery = PeerDiscovery(
      myId: myId!,
      myName: myName!,
      myTcpPort: _myPort,
      onPeer: (p) async {
        _relay.updatePeer(
          p['id'] as String,
          p['name'] as String? ?? p['id'],
          p['ip'] as String,
          p['port'] as int,
        );
        notifyListeners();
        await _relay.sendHello(p['id']);
      },
    );
    await _discovery!.start();
    _relay.start();
  }

  List<MeshUser> get peers => DbService.allUsers();
  List<MeshUser> get contacts =>
      DbService.allUsers().where((u) => u.id != myId).toList();

  List<MeshMessage> messagesWith(String peer) =>
      DbService.messagesWith(peer);

  Future<void> sendMessage(String to, String body) async {
    final msg = MeshMessage(
      id:
          'MSG-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}',
      from: myId!,
      to: to,
      body: body,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _relay.sendMessage(msg, toId: to);
    notifyListeners();
  }

  List<MeshMessage> get relayQueue => DbService.relayQueue();

  @override
  void dispose() {
    _server.stop();
    _discovery?.stop();
    _relay.stop();
    super.dispose();
  }
}
