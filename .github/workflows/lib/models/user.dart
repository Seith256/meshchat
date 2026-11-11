class MeshUser {
  final String id;
  final String name;
  final String? publicKey;
  int lastSeen;
  String? lastIp;
  int? lastPort;

  MeshUser({
    required this.id,
    required this.name,
    this.publicKey,
    this.lastSeen = 0,
    this.lastIp,
    this.lastPort,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pub': publicKey,
        'lastSeen': lastSeen,
        'ip': lastIp,
        'port': lastPort,
      };

  static MeshUser fromJson(Map<String, dynamic> j) => MeshUser(
        id: j['id'],
        name: j['name'],
        publicKey: j['pub'],
        lastSeen: j['lastSeen'] ?? 0,
        lastIp: j['ip'],
        lastPort: j['port'],
      );
}
