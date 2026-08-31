import 'dart:ffi';

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
    calloc.free(seckeyOut);
    calloc.free(pubkeyOut);
    bindings.destroy(wrapper);
  }
}
