import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'secp256k1_bindings.dart';

typedef NostrKeyPair = ({String privateKeyHex, String publicKeyHex});

int _hexDigit(int codeUnit) {
  if (codeUnit >= 0x30 && codeUnit <= 0x39) return codeUnit - 0x30;
  final lower = codeUnit | 0x20;
  if (lower >= 0x61 && lower <= 0x66) return lower - 0x61 + 10;
  return -1;
}

/// A secp256k1 secret key as bytes, so it can be zeroed once used.
class SecretKey {
  SecretKey._(this._bytes);

  /// Throws [ArgumentError] unless [hex] is 64 hex digits.
  factory SecretKey.fromHex(String hex) {
    if (hex.length != 64) throw ArgumentError('invalid hex length');
    final bytes = Uint8List(32);
    // Decoded by code unit, so no substrings of the secret are allocated.
    for (var i = 0; i < 32; i++) {
      final high = _hexDigit(hex.codeUnitAt(i * 2));
      final low = _hexDigit(hex.codeUnitAt(i * 2 + 1));
      if (high < 0 || low < 0) {
        bytes.fillRange(0, 32, 0);
        // Deliberately no value in the message: it is a secret.
        throw ArgumentError('invalid hex');
      }
      bytes[i] = high << 4 | low;
    }
    return SecretKey._(bytes);
  }

  final Uint8List _bytes;
  bool _wiped = false;

  /// Zeroes the key; any later use throws [StateError].
  void wipe() {
    _bytes.fillRange(0, _bytes.length, 0);
    _wiped = true;
  }

  void _copyInto(Pointer<Uint8> dest) {
    if (_wiped) throw StateError('secret key used after wipe');
    dest.asTypedList(32).setAll(0, _bytes);
  }

  @override
  String toString() => 'SecretKey(redacted)';
}

String _hexFromPointer(Pointer<Uint8> bytes, int length) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

void _wipe(Pointer<Uint8> buffer, int length) {
  for (var i = 0; i < length; i++) {
    buffer[i] = 0;
  }
}

final _sharedWrapper = () {
  final wrapper = NostrSecp256k1Bindings.instance.create();
  if (wrapper == nullptr) {
    throw StateError('nostr_secp256k1_create failed');
  }
  return wrapper;
}();

/// Derives the x-only public key hex, throwing [ArgumentError] if
/// [secretKey] is not a valid secret key.
String xonlyPubkeyHex(SecretKey secretKey) {
  final bindings = NostrSecp256k1Bindings.instance;
  final wrapper = _sharedWrapper;

  final seckey = calloc<Uint8>(32);
  final pubkeyOut = calloc<Uint8>(32);

  try {
    secretKey._copyInto(seckey);

    if (bindings.pubkeyFromSeckey(wrapper, seckey, pubkeyOut) != 1) {
      throw ArgumentError('invalid secp256k1 secret key');
    }

    return _hexFromPointer(pubkeyOut, 32);
  } finally {
    _wipe(seckey, 32);
    calloc.free(seckey);
    calloc.free(pubkeyOut);
  }
}

/// Generates a key pair. The native secret buffer is wiped; the returned hex
/// strings cannot be.
NostrKeyPair generateNostrKeyPair() {
  final bindings = NostrSecp256k1Bindings.instance;
  final wrapper = _sharedWrapper;

  final seckeyOut = calloc<Uint8>(32);
  final pubkeyOut = calloc<Uint8>(32);

  try {
    if (bindings.generateKeypair(wrapper, seckeyOut, pubkeyOut) != 1) {
      throw StateError('nostr_secp256k1_generate_keypair failed');
    }

    return (
      privateKeyHex: _hexFromPointer(seckeyOut, 32),
      publicKeyHex: _hexFromPointer(pubkeyOut, 32),
    );
  } finally {
    _wipe(seckeyOut, 32);
    calloc.free(seckeyOut);
    calloc.free(pubkeyOut);
  }
}

/// Signs the 32-byte [msg32] per BIP-340, throwing [ArgumentError] if
/// [secretKey] is not a valid secret key.
Uint8List signSchnorrSignature({
  required SecretKey secretKey,
  required Uint8List msg32,
}) {
  final bindings = NostrSecp256k1Bindings.instance;
  final wrapper = _sharedWrapper;

  final seckey = calloc<Uint8>(32);
  final msg = calloc<Uint8>(32);
  final sigOut = calloc<Uint8>(64);

  try {
    secretKey._copyInto(seckey);
    msg.asTypedList(32).setAll(0, msg32);

    if (bindings.signSchnorr(wrapper, seckey, msg, sigOut) != 1) {
      throw ArgumentError('invalid secp256k1 secret key');
    }

    return Uint8List.fromList(sigOut.asTypedList(64));
  } finally {
    _wipe(seckey, 32);
    calloc.free(seckey);
    calloc.free(msg);
    calloc.free(sigOut);
  }
}

/// Whether [sig64] is a valid BIP-340 signature of [msg32] by [pubkey32].
bool verifySchnorrSignature({
  required Uint8List msg32,
  required Uint8List sig64,
  required Uint8List pubkey32,
}) {
  final bindings = NostrSecp256k1Bindings.instance;
  final wrapper = _sharedWrapper;

  final msg = calloc<Uint8>(32);
  final sig = calloc<Uint8>(64);
  final pubkey = calloc<Uint8>(32);

  try {
    msg.asTypedList(32).setAll(0, msg32);
    sig.asTypedList(64).setAll(0, sig64);
    pubkey.asTypedList(32).setAll(0, pubkey32);

    return bindings.verifySchnorr(wrapper, msg, sig, pubkey) == 1;
  } finally {
    calloc.free(msg);
    calloc.free(sig);
    calloc.free(pubkey);
  }
}
