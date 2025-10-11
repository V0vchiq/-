import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

final speechServiceProvider = Provider<SpeechService>((ref) {
  return SpeechService();
});

class SpeechService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final StreamController<String> _controller = StreamController.broadcast();

  Stream<String> get onResult => _controller.stream;

  Future<bool> initialize() async {
    return _speech.initialize(onResult: (result) {
      if (result.recognizedWords.isNotEmpty) {
        _controller.add(result.recognizedWords);
      }
    }, localeId: 'ru_RU');
  }

  Future<void> start() async {
    await _speech.listen(localeId: 'ru_RU');
  }

  Future<void> stop() async {
    await _speech.stop();
  }

  void dispose() {
    _controller.close();
  }
}
