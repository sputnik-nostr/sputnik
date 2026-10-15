import 'dart:ffi';
import 'dart:io';

typedef _CreateNative = Pointer<Void> Function();
typedef CreateFn = Pointer<Void> Function();

typedef _PubkeyFromSeckeyNative = Int32 Function(
  Pointer<Void> wrapper,
  Pointer<Uint8> seckey32,
  Pointer<Uint8> pubkey32Out,
);
typedef PubkeyFromSeckeyFn = int Function(
  Pointer<Void> wrapper,
  Pointer<Uint8> seckey32,
  Pointer<Uint8> pubkey32Out,
);

typedef _GenerateKeypairNative = Int32 Function(
  Pointer<Void> wrapper,
  Pointer<Uint8> seckey32Out,
  Pointer<Uint8> pubkey32Out,
);
typedef GenerateKeypairFn = int Function(
  Pointer<Void> wrapper,
  Pointer<Uint8> seckey32Out,
  Pointer<Uint8> pubkey32Out,
);

typedef _VerifySchnorrNative = Int32 Function(
  Pointer<Void> wrapper,
  Pointer<Uint8> msg32,
  Pointer<Uint8> sig64,
  Pointer<Uint8> pubkey32,
);
typedef VerifySchnorrFn = int Function(
  Pointer<Void> wrapper,
  Pointer<Uint8> msg32,
  Pointer<Uint8> sig64,
  Pointer<Uint8> pubkey32,
);

typedef _SignSchnorrNative = Int32 Function(
  Pointer<Void> wrapper,
  Pointer<Uint8> seckey32,
  Pointer<Uint8> msg32,
  Pointer<Uint8> sig64Out,
);
typedef SignSchnorrFn = int Function(
  Pointer<Void> wrapper,
  Pointer<Uint8> seckey32,
  Pointer<Uint8> msg32,
  Pointer<Uint8> sig64Out,
);

DynamicLibrary _openNostrSecp256k1() {
  final override = Platform.environment['SPUTNIK_NOSTR_SECP256K1_LIBRARY'];
  if (override != null) return DynamicLibrary.open(override);

  if (Platform.isAndroid) return DynamicLibrary.open('libnostr_secp256k1.so');

  if (!Platform.isLinux) {
    throw UnsupportedError(
      'secp256k1 FFI bindings are only wired up for Linux and Android right now',
    );
  }

  final exeDir = File(Platform.resolvedExecutable).parent;
  final bundled = File('${exeDir.path}/lib/libnostr_secp256k1.so');
  if (bundled.existsSync()) return DynamicLibrary.open(bundled.path);

  throw StateError(
    'Could not find our vendored libnostr_secp256k1.so next to the running '
    'executable (${exeDir.path}). Build the Linux app with `flutter run -d '
    'linux` or `flutter build linux` so linux/CMakeLists.txt can bundle it.',
  );
}

class NostrSecp256k1Bindings {
  NostrSecp256k1Bindings._(DynamicLibrary lib)
    : create = lib.lookupFunction<_CreateNative, CreateFn>(
        'nostr_secp256k1_create',
      ),
      pubkeyFromSeckey = lib
          .lookupFunction<_PubkeyFromSeckeyNative, PubkeyFromSeckeyFn>(
            'nostr_secp256k1_pubkey_from_seckey',
          ),
      generateKeypair = lib
          .lookupFunction<_GenerateKeypairNative, GenerateKeypairFn>(
            'nostr_secp256k1_generate_keypair',
          ),
      verifySchnorr = lib.lookupFunction<_VerifySchnorrNative, VerifySchnorrFn>(
        'nostr_secp256k1_verify_schnorr',
      ),
      signSchnorr = lib.lookupFunction<_SignSchnorrNative, SignSchnorrFn>(
        'nostr_secp256k1_sign_schnorr',
      );

  static final NostrSecp256k1Bindings instance = NostrSecp256k1Bindings._(
    _openNostrSecp256k1(),
  );

  final CreateFn create;
  final PubkeyFromSeckeyFn pubkeyFromSeckey;
  final GenerateKeypairFn generateKeypair;
  final VerifySchnorrFn verifySchnorr;
  final SignSchnorrFn signSchnorr;
}
