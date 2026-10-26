import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// Hard AES-256-CBC encryption with PBKDF2-derived keys (requirement 7).
///
/// Passwords are never stored in plaintext. Ciphertext format:
/// `base64(iv):base64(ciphertext)`.
class EncryptionService {
  EncryptionService._();
  static final EncryptionService instance = EncryptionService._();

  static const int _keyLength = 32;
  static const int _ivLength = 16;
  static const int _pbkdf2Iterations = 100000;

  /// Derives a 256-bit key from [secret] + [salt] using PBKDF2-HMAC-SHA256.
  Uint8List deriveKey(String secret, String salt) {
    final saltBytes = utf8.encode(salt);
    final hmac = Hmac(sha256, utf8.encode(secret));
    // Simplified PBKDF2: iterative HMAC stretching
    var block = hmac.convert([...saltBytes, 0, 0, 0, 1]).bytes;
    var result = List<int>.from(block);
    for (var i = 1; i < _pbkdf2Iterations; i++) {
      block = hmac.convert(block).bytes;
      for (var j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }
    return Uint8List.fromList(result.sublist(0, _keyLength));
  }

  /// Generates a cryptographically random salt (hex).
  String generateSalt({int length = 32}) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Generates a random AES master key (base64).
  String generateMasterKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(_keyLength, (_) => random.nextInt(256));
    return base64Encode(bytes);
  }

  /// Wraps [masterKeyBase64] with a key derived from [secret] + [salt].
  /// Firestore only stores this ciphertext — never the raw master key.
  String wrapMasterKey(String masterKeyBase64, String secret, String salt) {
    final wrapKey = base64Encode(deriveKey(secret, salt));
    return encrypt(masterKeyBase64, wrapKey);
  }

  /// Unwraps a payload from [wrapMasterKey] using the same [secret] + [salt].
  String unwrapMasterKey(String wrappedPayload, String secret, String salt) {
    final wrapKey = base64Encode(deriveKey(secret, salt));
    return decrypt(wrappedPayload, wrapKey);
  }

  /// Encrypts [plainText] with [masterKeyBase64]. Returns `iv:ciphertext`.
  String encrypt(String plainText, String masterKeyBase64) {
    try {
      final key = enc.Key(base64Decode(masterKeyBase64));
      final iv = enc.IV.fromSecureRandom(_ivLength);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(plainText, iv: iv);
      return '${iv.base64}:${encrypted.base64}';
    } catch (e) {
      throw EncryptionException('Encrypt failed: $e');
    }
  }

  /// Decrypts [payload] (`iv:ciphertext`) with [masterKeyBase64].
  String decrypt(String payload, String masterKeyBase64) {
    try {
      final parts = payload.split(':');
      if (parts.length != 2) {
        throw EncryptionException('Invalid ciphertext format');
      }
      final key = enc.Key(base64Decode(masterKeyBase64));
      final iv = enc.IV.fromBase64(parts[0]);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      return encrypter.decrypt64(parts[1], iv: iv);
    } catch (e) {
      throw EncryptionException('Decrypt failed: $e');
    }
  }

  /// One-way SHA-256 hash for app PIN storage (never store raw PIN).
  String hashPin(String pin, String salt) {
    final digest = sha256.convert(utf8.encode('$salt::$pin'));
    return digest.toString();
  }

  /// Constant-time comparison for PIN hashes.
  bool verifyPin(String pin, String salt, String storedHash) {
    final computed = hashPin(pin, salt);
    if (computed.length != storedHash.length) return false;
    var result = 0;
    for (var i = 0; i < computed.length; i++) {
      result |= computed.codeUnitAt(i) ^ storedHash.codeUnitAt(i);
    }
    return result == 0;
  }
}

/// Thrown when encryption or decryption fails.
class EncryptionException implements Exception {
  EncryptionException(this.message);
  final String message;

  @override
  String toString() => 'EncryptionException: $message';
}
