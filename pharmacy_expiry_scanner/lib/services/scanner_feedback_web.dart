// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:js' as js;

import 'package:flutter/services.dart';

Future<void> playScanFeedback() async {
  await SystemSound.play(SystemSoundType.click);

  try {
    js.JsObject.fromBrowserObject(html.window.navigator).callMethod('vibrate', [
      [60],
    ]);
  } catch (_) {
    await HapticFeedback.mediumImpact();
  }
}
