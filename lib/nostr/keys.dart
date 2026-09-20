import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'hex.dart';
import 'secp256k1_bindings.dart';

typedef NostrKeyPair = ({String privateKeyHex, String publicKeyHex});

String _hexFromPointer(Pointer<Uint8> bytes, int length) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

void _bytesFromHexInto(Pointer<Uint8> dest, String hex, int length) {
  if (hex.length != length * 2) throw ArgumentError('invalid hex length');

  final Uint8List bytes;
  try {
    bytes = hexDecode(hex);
  } on FormatException {
    // Deliberately no value in the message: it may be a secret.
    throw ArgumentError('invalid hex');
  }
  try {
    dest.asTypedList(length).setAll(0, bytes);
  } finally {
    bytes.fillRange(0, bytes.length, 0);
  }
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
/// [seckeyHex] is not a valid secret key.
String xonlyPubkeyHexFromSeckeyHex(String seckeyHex) {
  final bindings = NostrSecp256k1Bindings.instance;
  final wrapper = _sharedWrapper;

  final seckey = calloc<Uint8>(32);
  final pubkeyOut = calloc<Uint8>(32);

  try {
    _bytesFromHexInto(seckey, seckeyHex, 32);

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
/// [seckeyHex] is not a valid secret key.
Uint8List signSchnorrSignature({
  required String seckeyHex,
  required Uint8List msg32,
}) {
  final bindings = NostrSecp256k1Bindings.instance;
  final wrapper = _sharedWrapper;

  final seckey = calloc<Uint8>(32);
  final msg = calloc<Uint8>(32);
  final sigOut = calloc<Uint8>(64);

  try {
    _bytesFromHexInto(seckey, seckeyHex, 32);
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
