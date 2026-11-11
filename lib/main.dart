import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:network_info_plus/network_info_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('identity');
  await Hive.openBox('users');
  await Hive.openBox('messages');
  await Hive.openBox('relay');
  runApp(const MeshChatApp());
}

class MeshChatApp extends StatelessWidget {
  const MeshChatApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MeshProvider()..init(),
      child: MaterialApp(
        title: 'MeshChat',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: Consumer<MeshProvider>(
          builder: (context, mesh, _) {
            if (mesh.loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            return mesh.myId == null ? const SetupScreen() : const HomeScreen();
          },
        ),
      ),
    );
  }
}

// ================= MODELS =================
class MeshUser {
  final String id; final String name; final String? publicKey;
  int lastSeen; String? lastIp; int? lastPort;
  MeshUser({required this.id, required this.name, this.publicKey, this.lastSeen = 0, this.lastIp, this.lastPort});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'pub': publicKey, 'lastSeen': lastSeen, 'ip': lastIp, 'port': lastPort};
  static MeshUser fromJson(Map<String, dynamic> j) => MeshUser(id: j['id'], name: j['name'], publicKey: j['pub'], lastSeen: j['lastSeen'] ?? 0, lastIp: j['ip'], lastPort: j['port']);
}

class MeshMessage {
  final String id; final String from; final String to; final String body;
  final String? ciphertext; final int createdAt; final int ttl; String status;
  MeshMessage({required this.id, required this.from, required this.to, required this.body, this.ciphertext, required this.createdAt, this.ttl = 7, this.status = 'queued'});
  Map<String, dynamic> toJson() => {'id': id, 'from': from, 'to': to, 'body': body, 'cipher': ciphertext, 'ts': createdAt, 'ttl': ttl, 'status': status};
  static MeshMessage fromJson(Map<String, dynamic> j) => MeshMessage(id: j['id'], from: j['from'], to: j['to'], body: j['body'] ?? '', ciphertext: j['cipher'], createdAt: j['ts'], ttl: j['ttl'] ?? 7, status: j['status'] ?? 'queued');
  MeshMessage copyWith({int? ttl, String? status, String? ciphertext}) => MeshMessage(id: id, from: from, to: to, body: body, ciphertext: ciphertext ?? this.ciphertext, createdAt: createdAt, ttl: ttl ?? this.ttl, status: status ?? this.status);
}

// ================= SERVICES =================
class DbService {
  static Box get _users => Hive.box('users');
  static Box get _messages => Hive.box('messages');
  static Box get _relay => Hive.box('relay');
  static Future<void> saveUser(MeshUser u) async => await _users.put(u.id, u.toJson());
  static MeshUser? getUser(String id) { final d = _users.get(id); return d == null ? null : MeshUser.fromJson(Map<String, dynamic>.from(d)); }
  static List<MeshUser> allUsers() => _users.values.map((i) => MeshUser.fromJson(Map<String, dynamic>.from(i))).toList();
  static Future<void> saveMessage(MeshMessage m) async => await _messages.put(m.id, m.toJson());
  static List<MeshMessage> messagesWith(String peerId) {
    final l = _messages.values.map((i) => MeshMessage.fromJson(Map<String, dynamic>.from(i))).where((m) => m.from == peerId || m.to == peerId).toList();
    l.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return l;
  }
  static MeshMessage? getMessage(String id) { final d = _messages.get(id); return d == null ? null : MeshMessage.fromJson(Map<String, dynamic>.from(d)); }
  static Future<void> enqueueRelay(MeshMessage m) async => await _relay.put(m.id, m.toJson());
  static Future<void> removeRelay(String id) async => await _relay.delete(id);
  static List<MeshMessage> relayQueue() => _relay.values.map((i) => MeshMessage.fromJson(Map<String, dynamic>.from(i))).toList();
}

class IdentityService {
  static const _b = 'identity';
  static String? get myId => Hive.box(_b).get('myId');
  static String? get myName => Hive.box(_b).get('myName');
  static String? get myPrivateKey => Hive.box(_b).get('priv');
  static String? get myPublicKey => Hive.box(_b).get('pub');
  static Future<void> create(String name) async {
    await Hive.box(_b).put('myId', 'USER-${List.generate(4, (_) => Random.secure().nextInt(16).toRadixString(16)).join().toUpperCase()}');
    await Hive.box(_b).put('myName', name);
  }
  static Future<void> saveKeys(String priv, String pub) async {
    await Hive.box(_b).put('priv', priv); await Hive.box(_b).put('pub', pub);
  }
}

class CryptoService {
  static final _x = X25519(); static final _a = AesGcm.with256bits();
  static Future<(String, String)> gen() async {
    final k = await _x.newKeyPair();
    return (base64Encode(await k.extractPrivateKeyBytes()), base64Encode((await k.extractPublicKey()).bytes));
  }
  static Future<String> encrypt(String p, String pubB64) async {
    final e = await _x.newKeyPair();
    final s = await _x.sharedSecretKey(keyPair: e, remotePublicKey: SimplePublicKey(base64Decode(pubB64), type: KeyPairType.x25519));
    final n = _a.newNonce();
    final b = await _a.encrypt(utf8.encode(p), secretKey: SecretKey(await s.extractBytes()), nonce: n);
    final ep = await e.extractPublicKey();
    return base64Encode((BytesBuilder()..add(ep.bytes)..add(b.nonce)..add(b.cipherText)..add(b.mac.bytes)).toBytes());
  }
  static Future<String> decrypt(String c, String myPriv) async {
    final d = base64Decode(c);
    final k = await _x.newKeyPairFromSeed(base64Decode(myPriv));
    final s = await _x.sharedSecretKey(keyPair: k, remotePublicKey: SimplePublicKey(d.sublist(0, 32), type: KeyPairType.x25519));
    final p = await _a.decrypt(SecretBox(d.sublist(44, d.length - 16), nonce: d.sublist(32, 44), mac: Mac(d.sublist(d.length - 16))), secretKey: SecretKey(await s.extractBytes()));
    return utf8.decode(p);
  }
}

class MeshClient {
  static Future<bool> send(String ip, int port, Map<String, dynamic> env) async {
    Socket? s;
    try {
      s = await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      final b = utf8.encode(jsonEncode(env));
      s.add([(b.length >> 24) & 0xff, (b.length >> 16) & 0xff, (b.length >> 8) & 0xff, b.length & 0xff, ...b]);
      await s.flush(); return true;
    } catch (_) { return false; } finally { s?.destroy(); }
  }
}

class MeshServer {
  final int port; final Function(Map<String, dynamic>) onEnv;
  MeshServer({required this.port, required this.onEnv});
  Future<void> start() async {
    final s = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    s.listen((c) {
      final b = <int>[];
      c.listen((d) => b.addAll(d), onDone: () {
        try {
          final l = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3];
          onEnv(jsonDecode(utf8.decode(b.sublist(4, 4 + l))));
        } catch (_) {} finally { c.destroy(); }
      });
    });
  }
}

class PeerDiscovery {
  final String id; final String name; final int port; final Function(Map<String, dynamic>) onPeer;
  PeerDiscovery({required this.id, required this.name, required this.port, required this.onPeer});
  Future<void> start() async {
    final s = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 48899, reuseAddress: true, reusePort: true);
    s.broadcastEnabled = true;
    s.listen((e) {
      if (e == RawSocketEvent.read) {
        final d = s.receive();
        if (d != null) {
          try {
            final m = jsonDecode(utf8.decode(d.data));
            if (m['tag'] == 'MESH_V1' && m['id'] != id) {
              onPeer({'id': m['id'], 'name': m['name'], 'ip': d.address.address, 'port': m['port']});
              s.send(utf8.encode(jsonEncode({'tag': 'MESH_V1', 'id': id, 'name': name, 'port': port})), d.address, 48899);
            }
          } catch (_) {}
        }
      }
    });
    Timer.periodic(const Duration(seconds: 5), (_) async {
      final p = utf8.encode(jsonEncode({'tag': 'MESH_V1', 'id': id, 'name': name, 'port': port}));
      s.send(p, InternetAddress('255.255.255.255'), 48899);
      try {
        final ip = await NetworkInfo().getWIFIIP();
        if (ip != null && ip.isNotEmpty) {
          final pts = ip.split('.');
          s.send(p, InternetAddress('${pts[0]}.${pts[1]}.${pts[2]}.255'), 48899);
        }
      } catch (_) {}
    });
  }
}

class RelayService {
  final Map<String, Map<String, dynamic>> peers = {}; final Set<String> _seen = {};
  void updatePeer(String id, String name, String ip, int port) {
    peers[id] = {'id': id, 'name': name, 'ip': ip, 'port': port};
    DbService.saveUser(MeshUser(id: id, name: name, publicKey: DbService.getUser(id)?.publicKey, lastSeen: DateTime.now().millisecondsSinceEpoch, lastIp: ip, lastPort: port));
  }
  Future<void> handle(Map<String, dynamic> e) async {
    final t = e['type']; final m = e['mid'];
    if (m != null) { if (_seen.contains(m)) return; _seen.add(m); }
    if (t == 'MSG') {
      if (e['to'] == IdentityService.myId) {
        try {
          final p = await CryptoService.decrypt(e['cipher'], IdentityService.myPrivateKey!);
          await DbService.saveMessage(MeshMessage(id: m, from: e['from'], to: e['to'], body: p, createdAt: e['ts'], status: 'delivered'));
          if (peers[e['from']] != null) await MeshClient.send(peers[e['from']]!['ip'], peers[e['from']]!['port'], {'type': 'ACK', 'mid': m, 'from': e['to']});
        } catch (_) {} return;
      }
      if ((e['ttl'] as int) > 1) {
        final r = MeshMessage(id: m, from: e['from'], to: e['to'], body: '', ciphertext: e['cipher'], createdAt: e['ts'], ttl: e['ttl'] - 1);
        await DbService.enqueueRelay(r); await forward(r);
      }
    } else if (t == 'ACK') {
      final msg = DbService.getMessage(m); if (msg != null) { msg.status = 'delivered'; await DbService.saveMessage(msg); } await DbService.removeRelay(m);
    } else if (t == 'HELLO') {
      final u = DbService.getUser(e['id']); if (u != null) { u.publicKey = e['pub']; DbService.saveUser(u); }
    }
  }
  Future<void> send(MeshMessage msg) async {
    final u = DbService.getUser(msg.to);
    if (u?.publicKey == null) return;
    final c = await CryptoService.encrypt(msg.body, u!.publicKey!);
    if (!await flood({'type': 'MSG', 'mid': msg.id, 'from': msg.from, 'to': msg.to, 'cipher': c, 'ts': msg.createdAt, 'ttl': 7})) {
      await DbService.enqueueRelay(msg);
    }
  }
  Future<void> forward(MeshMessage m) async {
    if (m.ciphertext == null) return;
    if (await flood({'type': 'MSG', 'mid': m.id, 'from': m.from, 'to': m.to, 'cipher': m.ciphertext, 'ts': m.createdAt, 'ttl': m.ttl})) await DbService.removeRelay(m.id);
  }
  Future<bool> flood(Map<String, dynamic> e) async {
    var ok = false; final d = peers[e['to']];
    if (d != null && await MeshClient.send(d['ip'], d['port'], e)) return true;
    for (final p in peers.values) { if (p['id'] != e['from'] && await MeshClient.send(p['ip'], p['port'], e)) ok = true; }
    return ok;
  }
}

// ================= PROVIDER =================
class MeshProvider extends ChangeNotifier {
  bool loading = true; String? myId; String? myName; int _port = 0;
  final RelayService _relay = RelayService();
  Future<void> init() async {
    if (IdentityService.myPrivateKey == null) { final k = await CryptoService.gen(); await IdentityService.saveKeys(k.$1, k.$2); }
    myId = IdentityService.myId; myName = IdentityService.myName; loading = false; notifyListeners();
    if (myId != null) await _boot();
  }
  Future<void> setup(String name) async { await IdentityService.create(name); myId = IdentityService.myId; myName = IdentityService.myName; notifyListeners(); await _boot(); }
  Future<void> _boot() async {
    _port = 40000 + Random().nextInt(10000);
    await MeshServer(port: _port, onEnv: (e) async { await _relay.handle(e); notifyListeners(); }).start();
    await PeerDiscovery(id: myId!, name: myName!, port: _port, onPeer: (p) async { _relay.updatePeer(p['id'], p['name'], p['ip'], p['port']); notifyListeners(); }).start();
    Timer.periodic(const Duration(seconds: 10), (_) async {
      for (final p in _relay.peers.values) { await MeshClient.send(p['ip'], p['port'], {'type': 'HELLO', 'id': myId, 'name': myName, 'pub': IdentityService.myPublicKey}); }
      for (final m in DbService.relayQueue()) { await _relay.forward(m); }
    });
  }
  List<MeshUser> get contacts => DbService.allUsers().where((u) => u.id != myId).toList();
  List<MeshMessage> messagesWith(String p) => DbService.messagesWith(p);
  List<MeshMessage> get relayQueue => DbService.relayQueue();
  Future<void> sendMessage(String to, String body) async {
    final m = MeshMessage(id: 'MSG-${DateTime.now().millisecondsSinceEpoch}', from: myId!, to: to, body: body, createdAt: DateTime.now().millisecondsSinceEpoch);
    await DbService.saveMessage(m); await _relay.send(m); notifyListeners();
  }
}

// ================= SCREENS =================
class SetupScreen extends StatefulWidget { const SetupScreen({super.key}); @override State<SetupScreen> createState() => _SetupScreenState(); }
class _SetupScreenState extends State<SetupScreen> {
  final _c = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Welcome')), body: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
      const Text('Offline Mesh Chat'), const SizedBox(height: 20),
      TextField(controller: _c, decoration: const InputDecoration(labelText: 'Your Name', border: OutlineInputBorder())),
      const SizedBox(height: 20), ElevatedButton(onPressed: () { if (_c.text.isNotEmpty) context.read<MeshProvider>().setup(_c.text); }, child: const Text('Start'))
    ])));
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final m = context.watch<MeshProvider>();
    return Scaffold(
      appBar: AppBar(title: Text('MeshChat - ${m.myName}')),
      body: m.contacts.isEmpty ? const Center(child: Text('Searching for peers...')) : ListView.builder(itemCount: m.contacts.length, itemBuilder: (c, i) {
        final u = m.contacts[i]; final msgs = m.messagesWith(u.id);
        return ListTile(leading: CircleAvatar(child: Text(u.name[0])), title: Text(u.name), subtitle: Text(msgs.isEmpty ? 'No messages' : msgs.last.body), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(peer: u.id, name: u.name))));
      }),
      bottomNavigationBar: BottomAppBar(child: Text('Relay Queue: ${m.relayQueue.length}', textAlign: TextAlign.center)),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String peer; final String name; const ChatScreen({super.key, required this.peer, required this.name}); @override State<ChatScreen> createState() => _ChatScreenState();
}
class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final m = context.watch<MeshProvider>(); final msgs = m.messagesWith(widget.peer);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(children: [
        Expanded(child: ListView.builder(itemCount: msgs.length, itemBuilder: (c, i) {
          final msg = msgs[i]; final me = msg.from == m.myId;
          return Align(alignment: me ? Alignment.centerRight : Alignment.centerLeft, child: Container(margin: const EdgeInsets.all(8), padding: const EdgeInsets.all(12), color: me ? Colors.teal.shade100 : Colors.grey.shade300, child: Text(msg.body)));
        })),
        Row(children: [
          Expanded(child: TextField(controller: _c)), IconButton(icon: const Icon(Icons.send), onPressed: () { if (_c.text.isNotEmpty) { m.sendMessage(widget.peer, _c.text); _c.clear(); } })
        ])
      ]),
    );
  }
}
