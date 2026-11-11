import 'dart:math';
import 'package:hive/hive.dart';

class IdentityService {
  static const _box = 'identity';

  static String? get myId => Hive.box(_box).get('myId');
  static String? get myName => Hive.box(_box).get('myName');
  static String? get myPrivateKey => Hive.box(_box).get('priv');
  static String? get myPublicKey => Hive.box(_box).get('pub');

  static Future<void> create({required String name}) async {
    final box = Hive.box(_box);
    final id = 'USER-${_randHex(4)}';
    await box.put('myId', id);
    await box.put('myName', name);
  }

  static Future<void> saveKeys(String priv, String pub) async {
    final box = Hive.box(_box);
    await box.put('priv', priv);
    await box.put('pub', pub);
  }

  static String _randHex(int len) {
    final r = Random.secure();
    return List.generate(len, (_) => r.nextInt(16).toRadixString(16))
        .join()
        .toUpperCase();
  }
}
