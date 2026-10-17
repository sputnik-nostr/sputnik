import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/error_reporting.dart';

/// Blocks network access from files; access-references=no breaks loadlist.
///
/// format_whitelist keeps out demuxers like DASH, which ignores
/// protocol_whitelist in older FFmpeg (e.g. 4.4 and 6.0).
const videoPlayerOptions = {
  'demuxer-lavf-o':
      'protocol_whitelist=file,format_whitelist=[mov,matroska,ogg]',
  'stream-lavf-o': 'protocol_whitelist=file',
  'ytdl': 'no',
  'load-scripts': 'no',
  'sub-auto': 'no',
  'audio-file-auto': 'no',
};

/// [value] as mpv reports it back, without the brackets that quote a list.
@visibleForTesting
String readBack(String value) => value.replaceAll(RegExp(r'[\[\]]'), '');

/// Applies [videoPlayerOptions], throwing unless every one took effect.
Future<void> lockDownPlayer(Player player) async {
  final platform = player.platform;
  if (platform is! NativePlayer) throw StateError('No native player');

  for (final option in videoPlayerOptions.entries) {
    await platform.setProperty(option.key, option.value);
    // setProperty ignores failure, and playing unlocked would be unsafe.
    if (await platform.getProperty(option.key) != readBack(option.value)) {
      throw StateError('Could not set ${option.key}');
    }
  }
}

/// Plays a local [file] with libmpv, with the network locked off.
class MediaKitPlayer extends StatefulWidget {
  const MediaKitPlayer({super.key, required this.file});

  final File file;

  @override
  State<MediaKitPlayer> createState() => _MediaKitPlayerState();
}

class _MediaKitPlayerState extends State<MediaKitPlayer> {
  Player? _player;
  VideoController? _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      MediaKit.ensureInitialized();
      final player = _player = Player();
      await lockDownPlayer(player);

      final controller = VideoController(player);
      await player.open(Media(widget.file.path));
      if (mounted) setState(() => _controller = controller);
    } catch (error, stack) {
      reportError('starting video playback', error, stack);
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (_failed) {
      return const Center(child: Text('Video playback is not available'));
    }
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Video(controller: controller);
  }
}
