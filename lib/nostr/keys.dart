import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'secp256k1_bindings.dart';

typedef NostrKeyPair = ({String privateKeyHex, String publicKeyHex});

String _hexFromPointer(Pointer<Uint8> bytes, int length) {
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

void _bytesFromHexInto(Pointer<Uint8> dest, String hex) {
  for (var i = 0; i * 2 < hex.length; i++) {
    dest[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
}

void _wipe(Pointer<Uint8> buffer, int length) {
  for (var i = 0; i < length; i++) {
    buffer[i] = 0;
  }
}

Pointer<Void> _createWrapper(NostrSecp256k1Bindings bindings) {
  final wrapper = bindings.create();
  if (wrapper == nullptr) {
    throw StateError('nostr_secp256k1_create failed');
  }
  return wrapper;
}

String xonlyPubkeyHexFromSeckeyHex(String seckeyHex) {
  final bindings = NostrSecp256k1Bindings.instance;
  final wrapper = _createWrapper(bindings);

  final seckey = calloc<Uint8>(32);
  final pubkeyOut = calloc<Uint8>(32);

  try {
    _bytesFromHexInto(seckey, seckeyHex);

    if (bindings.pubkeyFromSeckey(wrapper, seckey, pubkeyOut) != 1) {
      throw ArgumentError('invalid secp256k1 secret key');
    }

    return _hexFromPointer(pubkeyOut, 32);
  } finally {
    _wipe(seckey, 32);
    calloc.free(seckey);
    calloc.free(pubkeyOut);
    bindings.destroy(wrapper);
  }
}

NostrKeyPair generateNostrKeyPair() {
  final bindings = NostrSecp256k1Bindings.instance;
  final wrapper = _createWrapper(bindings);

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
    bindings.destroy(wrapper);
  }
}

bool verifySchnorrSignature({
  required Uint8List msg32,
  required Uint8List sig64,
  required Uint8List pubkey32,
}) {
  final bindings = NostrSecp256k1Bindings.instance;
  final wrapper = _createWrapper(bindings);

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
    bindings.destroy(wrapper);
  }
}
