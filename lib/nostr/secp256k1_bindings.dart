import 'dart:ffi';
import 'dart:io';

typedef _CreateNative = Pointer<Void> Function();
typedef CreateFn = Pointer<Void> Function();

typedef _DestroyNative = Void Function(Pointer<Void> wrapper);
typedef DestroyFn = void Function(Pointer<Void> wrapper);

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

DynamicLibrary _openNostrSecp256k1() {
  if (!Platform.isLinux) {
    throw UnsupportedError(
      'secp256k1 FFI bindings are only wired up for Linux right now',
    );
  }

  final override = Platform.environment['SPUTNIK_NOSTR_SECP256K1_LIBRARY'];
  if (override != null) return DynamicLibrary.open(override);

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
  NostrSecp256k1Bindings._(this._lib)
    : create = _lib.lookupFunction<_CreateNative, CreateFn>(
        'nostr_secp256k1_create',
      ),
      destroy = _lib.lookupFunction<_DestroyNative, DestroyFn>(
        'nostr_secp256k1_destroy',
      ),
      pubkeyFromSeckey = _lib
          .lookupFunction<_PubkeyFromSeckeyNative, PubkeyFromSeckeyFn>(
            'nostr_secp256k1_pubkey_from_seckey',
          ),
      generateKeypair = _lib
          .lookupFunction<_GenerateKeypairNative, GenerateKeypairFn>(
            'nostr_secp256k1_generate_keypair',
          );

  static final NostrSecp256k1Bindings instance = NostrSecp256k1Bindings._(
    _openNostrSecp256k1(),
  );

  final DynamicLibrary _lib;

  final CreateFn create;
  final DestroyFn destroy;
  final PubkeyFromSeckeyFn pubkeyFromSeckey;
  final GenerateKeypairFn generateKeypair;
}
