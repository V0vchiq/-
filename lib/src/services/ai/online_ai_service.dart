import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final onlineAiServiceProvider = Provider<OnlineAiService>((ref) {
  return OnlineAiService(Dio(), const FlutterSecureStorage());
});

class OnlineAiService {
  OnlineAiService(this._dio, this._storage);

  final Dio _dio;
  final FlutterSecureStorage _storage;

  static const _key = 'starmind_deepseek_token';

  Future<String?> generate(String prompt, {List<String> contexts = const []}) async {
    final token = await _storage.read(key: _key);
    if (token == null) {
      return null;
    }
    final payload = {
      'model': 'deepseek-chat',
      'messages': [
        {
          'role': 'system',
          'content': 'Отвечай на русском языке кратко и точно.'
        },
        if (contexts.isNotEmpty)
          {
            'role': 'system',
            'content': 'Контекст: ${contexts.join(' ')}',
          },
        {
          'role': 'user',
          'content': prompt,
        },
      ],
    };
    try {
      final response = await _dio.post(
        'https://api.deepseek.com/v1/chat/completions',
        data: payload,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }),
      );
      final choices = response.data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        return null;
      }
      return choices.first['message']['content'] as String?;
    } catch (_) {
      return null;
    }
  }
}
