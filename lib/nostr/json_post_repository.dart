import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models/nostr_post.dart';
import 'post_repository.dart';

class JsonPostRepository implements PostRepository {
  const JsonPostRepository({this.assetPath = 'posts.json'});

  final String assetPath;

  @override
  Future<List<NostrPost>> fetchPosts() async {
    final raw = await rootBundle.loadString(assetPath);
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final posts = decoded['posts'] as List<dynamic>;
    return posts.cast<Map<String, dynamic>>().map(NostrPost.fromJson).toList();
  }
}
