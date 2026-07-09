import 'package:flutter/services.dart';

Future<void> playScanFeedback() async {
  await SystemSound.play(SystemSoundType.click);
  await HapticFeedback.mediumImpact();
}
