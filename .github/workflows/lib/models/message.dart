import 'dart:convert';

class MeshMessage {
  final String id;
  final String from;
  final String to;
  final String body;
  final String? ciphertext;
  final int createdAt;
  final int ttl;
  String status;

  MeshMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.body,
    this.ciphertext,
    required this.createdAt,
    this.ttl = 7,
    this.status = 'queued',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'body': body,
        'cipher': ciphertext,
        'ts': createdAt,
        'ttl': ttl,
        'status': status,
      };

  static MeshMessage fromJson(Map<String, dynamic> j) => MeshMessage(
        id: j['id'],
        from: j['from'],
        to: j['to'],
        body: j['body'] ?? '',
        ciphertext: j['cipher'],
        createdAt: j['ts'],
        ttl: j['ttl'] ?? 7,
        status: j['status'] ?? 'queued',
      );

  MeshMessage copyWith({int? ttl, String? status, String? ciphertext}) =>
      MeshMessage(
        id: id,
        from: from,
        to: to,
        body: body,
        ciphertext: ciphertext ?? this.ciphertext,
        createdAt: createdAt,
        ttl: ttl ?? this.ttl,
        status: status ?? this.status,
      );
}
