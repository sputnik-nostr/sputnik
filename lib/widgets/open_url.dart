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

  var opened = false;
  try {
    opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on PlatformException {
    opened = false;
  } on MissingPluginException {
    opened = false;
  }
  if (!opened && context.mounted) _reportUnopenable(context);
}

void _reportUnopenable(BuildContext context) {
  ScaffoldMessenger.of(context)
      .showSnackBar(const SnackBar(content: Text('Could not open this link')));
}
