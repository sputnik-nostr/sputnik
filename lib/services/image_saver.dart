import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:gal/gal.dart';

import '../nostr/blossom.dart';
import 'media_loader.dart';

enum SaveOutcome { saved, cancelled, denied, failed }

class SaveResult {
  const SaveResult(this.outcome, [this.location]);

  final SaveOutcome outcome;

  /// Where the image went, for the message shown afterwards.
  final String? location;
}

/// The user said no to the permission that saving needs.
class SaveDenied implements Exception {
  const SaveDenied();
}

/// Stores [bytes] where the user can find them; null if they cancel.
typedef SaveBackend = Future<String?> Function(Uint8List bytes, String name);

const _imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];

/// The gallery on phones, and a file the user picks on desktop.
Future<String?> saveToDevice(Uint8List bytes, String name) async {
  if (Platform.isAndroid || Platform.isIOS) {
    if (!await Gal.requestAccess()) throw const SaveDenied();
    final dot = name.lastIndexOf('.');
    try {
      await Gal.putImageBytes(
        bytes,
        name: dot > 0 ? name.substring(0, dot) : name,
      );
    } on GalException catch (error) {
      if (error.type == GalExceptionType.accessDenied) throw const SaveDenied();
      rethrow;
    }
    return 'gallery';
  }

  final location = await getSaveLocation(
    suggestedName: name,
    acceptedTypeGroups: const [
      XTypeGroup(label: 'Images', extensions: _imageExtensions),
    ],
  );
  if (location == null) return null;
  await File(location.path).writeAsBytes(bytes);
  return location.path;
}

String? _sniffedExtension(List<int> b) {
  bool starts(List<int> magic, [int at = 0]) {
    if (b.length < at + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (b[at + i] != magic[i]) return false;
    }
    return true;
  }

  if (starts([0x89, 0x50, 0x4e, 0x47])) return '.png';
  if (starts([0xff, 0xd8, 0xff])) return '.jpg';
  if (starts('GIF8'.codeUnits)) return '.gif';
  if (starts('RIFF'.codeUnits) && starts('WEBP'.codeUnits, 8)) return '.webp';
  if (starts('BM'.codeUnits)) return '.bmp';
  return null;
}

/// A safe file name for [bytes] fetched from [url], whatever the URL claims.
String imageFileName(String url, List<int> bytes) {
  final uri = Uri.tryParse(url);
  final last = uri == null || uri.pathSegments.isEmpty
      ? ''
      : uri.pathSegments.last;
  final dot = last.lastIndexOf('.');
  var stem = (dot > 0 ? last.substring(0, dot) : last)
      .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
      .replaceFirst(RegExp(r'^\.+'), '');
  if (stem.length > 60) stem = stem.substring(0, 60);
  if (stem.isEmpty) stem = 'image';

  final urlExtension = uri == null ? '' : extensionOf(uri).toLowerCase();
  final extension =
      _sniffedExtension(bytes) ??
      (_imageExtensions.contains(urlExtension.replaceFirst('.', ''))
          ? urlExtension
          : '');
  return '$stem$extension';
}

Future<Uint8List> _fetchOriginal(MediaSource source) {
  return source.fetch((uri) => fetchImageBytes(uri, sha256: source.sha256));
}

/// Downloads the original image at [source] and saves it.
Future<SaveResult> saveImage(
  MediaSource source, {
  SaveBackend backend = saveToDevice,
  Future<Uint8List> Function(MediaSource source) fetchBytes = _fetchOriginal,
}) async {
  final Uint8List bytes;
  try {
    bytes = await fetchBytes(source);
  } catch (_) {
    return const SaveResult(SaveOutcome.failed);
  }

  try {
    final location = await backend(bytes, imageFileName(source.url, bytes));
    if (location == null) return const SaveResult(SaveOutcome.cancelled);
    return SaveResult(SaveOutcome.saved, location);
  } on SaveDenied {
    return const SaveResult(SaveOutcome.denied);
  } catch (_) {
    return const SaveResult(SaveOutcome.failed);
  }
}

/// What to tell the user about [result], or null if nothing needs saying.
String? saveMessage(SaveResult result) {
  return switch (result.outcome) {
    SaveOutcome.saved => 'Saved to ${result.location}',
    SaveOutcome.cancelled => null,
    SaveOutcome.denied => 'Permission to save images was denied',
    SaveOutcome.failed => 'Could not save this image',
  };
}
