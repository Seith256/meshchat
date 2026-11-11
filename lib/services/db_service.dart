import 'package:hive/hive.dart';
import '../models/message.dart';
import '../models/user.dart';

class DbService {
  static Box get _users => Hive.box('users');
  static Box get _messages => Hive.box('messages');
  static Box get _relay => Hive.box('relay');

  static Future<void> saveUser(MeshUser u) => _users.put(u.id, u.toJson());
  static MeshUser? getUser(String id) {
    final j = _users.get(id);
    return j == null
        ? null
        : MeshUser.fromJson(Map<String, dynamic>.from(j));
  }

  static List<MeshUser> allUsers() => _users.values
      .map((j) => MeshUser.fromJson(Map<String, dynamic>.from(j)))
      .toList();

  static Future<void> saveMessage(MeshMessage m) =>
      _messages.put(m.id, m.toJson());

  static List<MeshMessage> messagesWith(String peer) {
    final list = _messages.values
        .map((j) => MeshMessage.fromJson(Map<String, dynamic>.from(j)))
        .where((m) => m.from == peer || m.to == peer)
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  static MeshMessage? getMessage(String id) {
    final j = _messages.get(id);
    return j == null
        ? null
        : MeshMessage.fromJson(Map<String, dynamic>.from(j));
  }

  static Future<void> enqueueRelay(MeshMessage m) =>
      _relay.put(m.id, m.toJson());
  static Future<void> removeRelay(String id) => _relay.delete(id);
  static List<MeshMessage> relayQueue() => _relay.values
      .map((j) => MeshMessage.fromJson(Map<String, dynamic>.from(j)))
      .toList();
}
