import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final modelServiceProvider = Provider<ModelService>((ref) {
  return ModelService();
});

enum ModelType { offline, online }

class AIModel {
  final String id;
  final String name;
  final String? size;
  final String? description;
  final ModelType type;
  final String? url;
  final int? sizeBytes;

  const AIModel({
    required this.id,
    required this.name,
    this.size,
    this.description,
    required this.type,
    this.url,
    this.sizeBytes,
  });
}

class ModelDownloadState {
  final String? modelId;
  final double progress;
  final String status;
  
  const ModelDownloadState({
    this.modelId,
    this.progress = 0,
    this.status = 'idle',
  });
}

final modelDownloadStateProvider = StateProvider<ModelDownloadState>((ref) {
  return const ModelDownloadState();
});

final selectedModelProvider = StateProvider<AIModel?>((ref) => null);

class ModelService {
  static const _downloadChannel = MethodChannel('nexus/download');
  static const _progressChannel = EventChannel('nexus/download/progress');
  
  StreamSubscription? _progressSubscription;

  static const List<AIModel> availableModels = [
    // Офлайн модели (от лёгкой к тяжёлой)
    AIModel(
      id: 'llama32-1b-q8',
      name: 'Llama 3.2 1B',
      size: '1.3 GB',
      description: 'Компактная и быстрая',
      type: ModelType.offline,
      url: 'https://5425258b-0062-47c0-9ab3-07331659a0d7.selstorage.ru/Free/Llama-3.2-1B-Instruct-Q8_0.gguf',
      sizeBytes: 1300000000,
    ),
    AIModel(
      id: 'qwen25-coder-15b',
      name: 'Qwen 2.5 Coder 1.5B',
      size: '1.3 GB',
      description: 'Несложный код',
      type: ModelType.offline,
      url: 'https://5425258b-0062-47c0-9ab3-07331659a0d7.selstorage.ru/Free/qwen2.5-coder-1.5b-instruct-q6_k.gguf',
      sizeBytes: 1390000000,
    ),
    AIModel(
      id: 'gemma2-2b-q5km',
      name: 'Gemma 2 2B',
      size: '1.9 GB',
      description: 'Отличная универсальная модель, хорошо составляет и переводит тексты',
      type: ModelType.offline,
      url: 'https://5425258b-0062-47c0-9ab3-07331659a0d7.selstorage.ru/gemma-2-2b-it-q5_k_m.gguf',
      sizeBytes: 1920000000,
    ),
    AIModel(
      id: 'ministral3-3b-q5km',
      name: 'Ministral 3 3B',
      size: '2.1 GB',
      description: 'Хорошее понимание деталей и рассуждение',
      type: ModelType.offline,
      url: 'https://5425258b-0062-47c0-9ab3-07331659a0d7.selstorage.ru/Free/Ministral-3-3B-Instruct-2512-Q5_K_M.gguf',
      sizeBytes: 2200000000,
    ),
    AIModel(
      id: 'phi35-mini-q4km',
      name: 'Phi 3.5 mini',
      size: '2.2 GB',
      description: 'Логика, рассуждения',
      type: ModelType.offline,
      url: 'https://5425258b-0062-47c0-9ab3-07331659a0d7.selstorage.ru/Free/Phi-3.5-mini-instruct-Q4_K_M.gguf',
      sizeBytes: 2300000000,
    ),
    AIModel(
      id: 'llama32-3b-q5km',
      name: 'Llama 3.2 3B',
      size: '2.5 GB',
      description: 'Диалоги, общение, рассуждения',
      type: ModelType.offline,
      url: 'https://5425258b-0062-47c0-9ab3-07331659a0d7.selstorage.ru/Paid/Llama-3.2-3B-Instruct-Q5_K_M.gguf',
      sizeBytes: 2600000000,
    ),
    AIModel(
      id: 'deepseek-coder-67b',
      name: 'DeepSeek Coder 6.7B',
      size: '4.0 GB',
      description: 'Модель для сложного кодинга на разных ЯП',
      type: ModelType.offline,
      url: 'https://5425258b-0062-47c0-9ab3-07331659a0d7.selstorage.ru/Paid/deepseek-coder-6.7b-instruct.Q4_K_M.gguf',
      sizeBytes: 4200000000,
    ),
    AIModel(
      id: 'llama31-8b-q4km',
      name: 'Llama 3.1 8B',
      size: '4.9 GB',
      description: 'Универсальная модель для сложных вопросов',
      type: ModelType.offline,
      url: 'https://5425258b-0062-47c0-9ab3-07331659a0d7.selstorage.ru/Paid/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf',
      sizeBytes: 5100000000,
    ),
    AIModel(
      id: 'saiga-yandexgpt-8b',
      name: 'Saiga YandexGPT 8B',
      size: '5.0 GB',
      description: 'Российская модель, подробные и качественные ответы',
      type: ModelType.offline,
      url: 'https://5425258b-0062-47c0-9ab3-07331659a0d7.selstorage.ru/Paid/saiga_yandexgpt_8b.Q4_K_M.gguf',
      sizeBytes: 5200000000,
    ),
    // Онлайн модели
    AIModel(
      id: 'deepseek',
      name: 'DeepSeek V3.2',
      size: null,
      description: 'Проверка информации и фактов',
      type: ModelType.online,
    ),
  ];

  void listenToProgress(void Function(ModelDownloadState) onProgress) {
    _progressSubscription?.cancel();
    _progressSubscription = _progressChannel.receiveBroadcastStream().listen((event) {
      final data = event as Map;
      onProgress(ModelDownloadState(
        modelId: data['modelId'] as String?,
        progress: (data['progress'] as num?)?.toDouble() ?? 0,
        status: data['status'] as String? ?? 'unknown',
      ));
    });
  }

  void stopListening() {
    _progressSubscription?.cancel();
    _progressSubscription = null;
  }

  Future<void> startDownload(AIModel model) async {
    if (model.type != ModelType.offline || model.url == null) return;
    
    await _downloadChannel.invokeMethod('startDownload', {
      'modelId': model.id,
      'modelName': model.name,
      'modelUrl': model.url,
      'modelSize': model.sizeBytes,
    });
  }

  Future<void> cancelDownload() async {
    await _downloadChannel.invokeMethod('cancelDownload');
  }

  Future<bool> isDownloading() async {
    return await _downloadChannel.invokeMethod('isDownloading') ?? false;
  }

  Future<bool> isModelDownloaded(String modelId) async {
    return await _downloadChannel.invokeMethod('isModelDownloaded', modelId) ?? false;
  }

  Future<String?> getModelPath(String modelId) async {
    return await _downloadChannel.invokeMethod('getModelPath', modelId);
  }

  Future<bool> deleteModel(String modelId) async {
    return await _downloadChannel.invokeMethod('deleteModel', modelId) ?? false;
  }

  AIModel? getModelById(String id) {
    try {
      return availableModels.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  List<AIModel> getOfflineModels() {
    return availableModels.where((m) => m.type == ModelType.offline).toList();
  }

  List<AIModel> getOnlineModels() {
    return availableModels.where((m) => m.type == ModelType.online).toList();
  }
}
