import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final phiServiceProvider = Provider<PhiService>((ref) {
  return PhiService();
});

class PhiService {
  final MethodChannel _channel = const MethodChannel('starmind/phi');
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    try {
      await _channel.invokeMethod('loadModel');
      _loaded = true;
    } catch (_) {
      _loaded = false;
    }
  }

  Future<String?> generate(String prompt, {List<String> contexts = const []}) async {
    if (!_loaded) {
      return null;
    }
    try {
      final response = await _channel.invokeMethod<String>('generate', {
        'prompt': prompt,
        'contexts': contexts,
      });
      return response;
    } catch (_) {
      return null;
    }
  }
}
