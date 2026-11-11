import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();

  static Future<(String, String)> generateKeypair() async {
    final kp = await _x25519.newKeyPair();
    final priv = await kp.extractPrivateKeyBytes();
    final pub = await kp.extractPublicKey();
    return (base64Encode(priv), base64Encode(pub.bytes));
  }

  static Future<String> encryptFor(String plain, String recipientPubB64) async {
    final recipientPub = SimplePublicKey(
      base64Decode(recipientPubB64),
      type: KeyPairType.x25519,
    );
    final eph = await _x25519.newKeyPair();
    final shared = await _x25519.sharedSecretKey(
      keyPair: eph,
      remotePublicKey: recipientPub,
    );
    final aesKey = await shared.extractBytes();
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(plain),
      secretKey: SecretKey(aesKey),
      nonce: nonce,
    );
    final ephPub = await eph.extractPublicKey();
    final combined = BytesBuilder()
      ..add(ephPub.bytes)
      ..add(box.nonce)
      ..add(box.cipherText)
      ..add(box.mac.bytes);
    return base64Encode(combined.toBytes());
  }

  static Future<String> decrypt(String b64Cipher, String myPrivB64) async {
    final data = base64Decode(b64Cipher);
    final ephPubBytes = data.sublist(0, 32);
    final nonce = data.sublist(32, 44);
    final mac = data.sublist(data.length - 16);
    final cipher = data.sublist(44, data.length - 16);

    final myKeyPair =
        await _x25519.newKeyPairFromSeed(base64Decode(myPrivB64));
    final shared = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(ephPubBytes, type: KeyPairType.x25519),
    );
    final aesKey = await shared.extractBytes();

    final plain = await _aes.decrypt(
      SecretBox(cipher, nonce: nonce, mac: Mac(mac)),
      secretKey: SecretKey(aesKey),
    );
    return utf8.decode(plain);
  }
}
