import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ragServiceProvider = Provider<RagService>((ref) {
  return RagService();
});

class RagService {
  final MethodChannel _channel = const MethodChannel('starmind/faiss');
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    try {
      await _channel.invokeMethod('loadIndex');
      _loaded = true;
    } catch (_) {
      _loaded = false;
    }
  }

  Future<List<String>> retrieve(String query) async {
    if (!_loaded) {
      return const [];
    }
    try {
      final result = await _channel.invokeMethod<List<dynamic>>('search', {
        'query': query,
        'topK': 4,
      });
      return result?.cast<String>() ?? const [];
    } catch (_) {
      return const [];
    }
  }
}
