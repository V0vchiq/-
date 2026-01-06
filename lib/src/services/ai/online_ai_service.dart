import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final onlineAiServiceProvider = Provider<OnlineAiService>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    sendTimeout: const Duration(seconds: 15),
  ));
  return OnlineAiService(dio, const FlutterSecureStorage());
});

class OnlineAiService {
  OnlineAiService(this._dio, this._storage);

  final Dio _dio;
  final FlutterSecureStorage _storage;
  CancelToken? _cancelToken;

  static const _deepseekKey = 'nexus_deepseek_token';
  static const _defaultDeepSeekKey = 'sk-2f926e2bcf3f455cb8fa0db469349d3a';

  void cancelStream() {
    _cancelToken?.cancel('User cancelled');
    _cancelToken = null;
  }

  Future<void> setApiKey(String apiKey) async {
    await _storage.write(key: _deepseekKey, value: apiKey);
  }

  Future<String?> getApiKey() async {
    try {
      return await _storage.read(key: _deepseekKey);
    } catch (_) {
      return null;
    }
  }

  Future<String?> generate(String prompt, {List<String> contexts = const []}) async {
    String? token;
    try {
      token = await _storage.read(key: _deepseekKey);
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) {
      token = _defaultDeepSeekKey;
    }
    if (token.isEmpty) return null;

    final payload = {
      'model': 'deepseek-chat',
      'messages': _buildMessages(prompt, contexts),
    };
    try {
      debugPrint('[DeepSeek] Sending request...');
      final response = await _dio.post(
        'https://api.deepseek.com/v1/chat/completions',
        data: payload,
        options: Options(headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }),
      );
      debugPrint('[DeepSeek] Response received');
      return _extractResponse(response.data);
    } catch (e) {
      debugPrint('[DeepSeek] Error: $e');
      return null;
    }
  }

  List<Map<String, String>> _buildMessages(String prompt, List<String> contexts) {
    final userContent = contexts.isNotEmpty
        ? 'Контекст: ${contexts.join(' ')}\n\n$prompt'
        : prompt;
    return [
      {'role': 'user', 'content': userContent},
    ];
  }

  String? _extractResponse(dynamic data) {
    final choices = data['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) return null;
    return choices.first['message']['content'] as String?;
  }

  /// Стриминг генерации для онлайн API
  Stream<String> generateStream(String prompt, {List<Map<String, String>> history = const []}) async* {
    String? token;
    try {
      token = await _storage.read(key: _deepseekKey);
    } catch (_) {
      token = null;
    }
    if (token == null || token.isEmpty) {
      token = _defaultDeepSeekKey;
    }
    if (token.isEmpty) return;

    final messages = <Map<String, String>>[
      ...history,
      {'role': 'user', 'content': prompt},
    ];

    final payload = {
      'model': 'deepseek-chat',
      'messages': messages,
      'stream': true,
    };

    try {
      debugPrint('[DeepSeek] Starting stream...');
      _cancelToken = CancelToken();
      final response = await _dio.post<ResponseBody>(
        'https://api.deepseek.com/v1/chat/completions',
        data: payload,
        cancelToken: _cancelToken,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          responseType: ResponseType.stream,
        ),
      );

      final stream = response.data?.stream;
      if (stream == null) return;

      String buffer = '';
      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
        
        // Парсим SSE события
        final lines = buffer.split('\n');
        buffer = lines.last; // Оставляем неполную строку в буфере
        
        for (final line in lines.take(lines.length - 1)) {
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') continue;
            
            try {
              final json = jsonDecode(data);
              final delta = json['choices']?[0]?['delta']?['content'] as String?;
              if (delta != null && delta.isNotEmpty) {
                yield delta;
              }
            } catch (_) {}
          }
        }
      }
      debugPrint('[DeepSeek] Stream completed');
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) {
        debugPrint('[DeepSeek] Stream cancelled by user');
      } else {
        debugPrint('[DeepSeek] Stream error: $e');
      }
    } catch (e) {
      debugPrint('[DeepSeek] Stream error: $e');
    } finally {
      _cancelToken = null;
    }
  }
}
