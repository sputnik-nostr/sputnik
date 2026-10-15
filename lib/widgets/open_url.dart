import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser, or says so if that isn't possible.
Future<void> openExternalUrl(BuildContext context, String url) async {
  final Uri uri;
  try {
    uri = Uri.parse(url);
  } on FormatException {
    _reportUnopenable(context);
    return;
  }

  final opened = await launchExternal(uri);
  if (!opened && context.mounted) _reportUnopenable(context);
}

/// Hands [uri] to another app; false if none could take it.
Future<bool> launchExternal(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}

void _reportUnopenable(BuildContext context) {
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Could not open this link')));
}
