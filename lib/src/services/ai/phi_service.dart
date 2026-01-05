import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'model_service.dart';

final phiServiceProvider = Provider<PhiService>((ref) {
  final service = PhiService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});

class PhiService {
  PhiService(this._ref);

  final Ref _ref;
  final MethodChannel _channel = const MethodChannel('nexus/llama');
  final MethodChannel _downloadChannel = const MethodChannel('nexus/download');
  final EventChannel _streamChannel = const EventChannel('nexus/llama/stream');
  bool _loaded = false;
  String? _loadedModelId;
  Future<void>? _loading;
  StreamSubscription? _tokenSubscription;

  Future<void> ensureLoaded() async {
    final selectedModel = _ref.read(selectedModelProvider);
    final modelId = selectedModel?.id ?? 'gemma2-2b-q5km';
    
    // Если загружена другая модель - перезагружаем
    if (_loaded && _loadedModelId != modelId) {
      debugPrint('PhiService: switching model from $_loadedModelId to $modelId');
      _loaded = false;
      _loadedModelId = null;
    }
    
    if (_loaded) {
      return;
    }
    if (_loading != null) {
      await _loading;
      return;
    }
    _loading = _load(modelId);
    try {
      await _loading;
    } finally {
      _loading = null;
    }
  }

  Future<void> _load(String modelId) async {
    try {
      final modelPath = await _downloadChannel.invokeMethod<String>('getModelPath', modelId);
      
      if (modelPath == null) {
        debugPrint('PhiService: model $modelId not downloaded');
        _loaded = false;
        return;
      }
      
      debugPrint('PhiService: loading model from: $modelPath');
      await _channel.invokeMethod('loadModel', {
        'modelPath': modelPath,
      });
      _loaded = true;
      _loadedModelId = modelId;
      debugPrint('PhiService: model loaded');
    } catch (error, stackTrace) {
      debugPrint('PhiService: failed to load offline model: $error');
      debugPrint('$stackTrace');
      _loaded = false;
    }
  }

  /// Выгружает модель из памяти
  Future<void> unloadModel() async {
    if (!_loaded) return;
    
    try {
      await _channel.invokeMethod('unloadModel');
      _loaded = false;
      _loadedModelId = null;
      debugPrint('PhiService: model unloaded');
    } catch (e) {
      debugPrint('PhiService: failed to unload model: $e');
    }
  }

  /// Освобождает ресурсы
  void dispose() {
    _tokenSubscription?.cancel();
    _tokenSubscription = null;
    debugPrint('PhiService: disposed');
  }

  /// Останавливает текущую генерацию
  Future<void> stopGeneration() async {
    try {
      await _channel.invokeMethod('stopGeneration');
      _tokenSubscription?.cancel();
      debugPrint('PhiService: generation stopped');
    } catch (e) {
      debugPrint('PhiService: failed to stop generation: $e');
    }
  }

  Future<String?> generate(String prompt, {List<String> contexts = const []}) async {
    await ensureLoaded();
    if (!_loaded) {
      return null;
    }
    try {
      final fullPrompt = _buildPrompt(prompt, contexts);
      final response = await _channel.invokeMethod<String>('generate', {
        'prompt': fullPrompt,
      });
      return _sanitizeResponse(response);
    } catch (_) {
      return null;
    }
  }

  /// Стриминг генерации - возвращает токены по мере генерации
  Stream<String> generateStream(String prompt) {
    final controller = StreamController<String>();
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    
    _startStreaming(prompt, requestId, controller);
    
    return controller.stream;
  }
  
  Future<void> _startStreaming(String prompt, String requestId, StreamController<String> controller) async {
    await ensureLoaded();
    if (!_loaded) {
      controller.close();
      return;
    }

    // Подписываемся на EventChannel
    _tokenSubscription?.cancel();
    _tokenSubscription = _streamChannel.receiveBroadcastStream().listen(
      (event) {
        final data = event as Map;
        final eventRequestId = data['requestId'] as String?;
        final token = data['token'] as String?;
        
        // Игнорируем токены от других запросов
        if (eventRequestId != requestId || token == null) return;
        
        if (token == '[DONE]') {
          _tokenSubscription?.cancel();
          controller.close();
        } else if (token == '[ERROR]') {
          _tokenSubscription?.cancel();
          controller.addError('Generation error');
          controller.close();
        } else {
          controller.add(token);
        }
      },
      onError: (error) {
        _tokenSubscription?.cancel();
        controller.addError(error);
        controller.close();
      },
    );

    // Запускаем генерацию с requestId
    try {
      await _channel.invokeMethod('generateStream', {
        'prompt': prompt,
        'requestId': requestId,
      });
    } catch (e) {
      _tokenSubscription?.cancel();
      controller.addError(e);
      controller.close();
    }
  }

  String _buildPrompt(String prompt, List<String> contexts) {
    final contextBlock = contexts.isNotEmpty
        ? 'Контекст: ${contexts.join(' ')}\n\n'
        : '';
    final userMessage = '$contextBlock$prompt';
    return _formatSingleTurn(userMessage);
  }

  /// Публичный метод для построения промпта с историей (для стриминга)
  String buildPromptForStreaming(String prompt, {List<Map<String, String>> history = const []}) {
    return _buildPromptWithHistory(prompt, history);
  }
  
  String _buildPromptWithHistory(String prompt, List<Map<String, String>> history) {
    return _formatMultiTurn(history, prompt);
  }
  
  /// Форматирует одиночный запрос (без истории)
  String _formatSingleTurn(String userMessage) {
    final prompt = '<start_of_turn>user\n$userMessage<end_of_turn>\n<start_of_turn>model\n';
    debugPrint('===== PROMPT TO MODEL =====');
    debugPrint(prompt);
    debugPrint('===========================');
    return prompt;
  }
  
  /// Форматирует мультитёрн диалог с историей
  String _formatMultiTurn(List<Map<String, String>> history, String currentPrompt) {
    final buffer = StringBuffer();
    
    for (final msg in history) {
      if (msg['role'] == 'user') {
        buffer.write('<start_of_turn>user\n${msg['content']}<end_of_turn>\n');
      } else {
        buffer.write('<start_of_turn>model\n${msg['content']}<end_of_turn>\n');
      }
    }
    
    buffer.write('<start_of_turn>user\n$currentPrompt<end_of_turn>\n<start_of_turn>model\n');
    
    final prompt = buffer.toString();
    debugPrint('===== PROMPT TO MODEL =====');
    debugPrint(prompt);
    debugPrint('===========================');
    return prompt;
  }

  /// Публичный метод для очистки ответа
  String? sanitizeResponse(String? raw) => _sanitizeResponse(raw);

  String? _sanitizeResponse(String? raw) {
    debugPrint('===== RAW RESPONSE =====');
    debugPrint(raw ?? 'null');
    debugPrint('========================');
    
    if (raw == null) return null;
    var text = raw.trim();
    if (text.isEmpty) return null;

    // Стоп-токены для всех форматов
    final stopTokens = [
      'Пользователь:',
      'Ты — русскоязычный',
      '\n\nТы —',
      '<end_of_turn>',
      '<|eot_id|>',
      '<|im_end|>',
      '<|end|>',
      '<|endoftext|>',
      '</s>',
      '[INST]',
      '<start_of_turn>',
      '<|start_header_id|>',
      '<|im_start|>',
      '<|user|>',
    ];
    
    for (final token in stopTokens) {
      final idx = text.indexOf(token);
      if (idx != -1) {
        debugPrint('Found stop token: $token');
        text = text.substring(0, idx).trim();
      }
    }

    final trimmed = text.trim();
    debugPrint('===== CLEAN RESPONSE =====');
    debugPrint(trimmed.isEmpty ? 'EMPTY' : trimmed);
    debugPrint('==========================');
    return trimmed.isEmpty ? null : trimmed;
  }
}