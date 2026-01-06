import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../services/ai/model_service.dart';
import '../../../../services/ai/phi_service.dart';

class ModelSelectorScreen extends ConsumerStatefulWidget {
  const ModelSelectorScreen({super.key});

  @override
  ConsumerState<ModelSelectorScreen> createState() => _ModelSelectorScreenState();
}

class _ModelSelectorScreenState extends ConsumerState<ModelSelectorScreen>
    with SingleTickerProviderStateMixin {
  static const _systemChannel = MethodChannel('nexus/system');
  
  Map<String, bool> _downloadedStatus = {};
  bool _loading = true;
  ModelService? _modelService;
  
  // Память
  int? _freeStorage;
  int? _totalStorage;
  int? _freeRam;
  int? _totalRam;
  
  // Анимация предупреждения
  late AnimationController _warningAnimController;
  late Animation<double> _warningFadeAnim;
  bool _showWarning = true;

  @override
  void initState() {
    super.initState();
    _modelService = ref.read(modelServiceProvider);
    _loadModelStatuses();
    _listenToDownloadProgress();
    _loadMemoryInfo();
    
    // Инициализация анимации предупреждения
    _warningAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _warningFadeAnim = CurvedAnimation(
      parent: _warningAnimController,
      curve: Curves.easeInOut,
    );
    _warningAnimController.forward();
  }
  
  Future<void> _loadMemoryInfo() async {
    try {
      final result = await _systemChannel.invokeMethod<Map>('getMemoryInfo');
      if (result != null && mounted) {
        setState(() {
          _totalStorage = result['totalStorage'] as int?;
          _freeStorage = result['freeStorage'] as int?;
          _totalRam = result['totalRam'] as int?;
          _freeRam = result['freeRam'] as int?;
        });
      }
    } catch (e) {
      debugPrint('Failed to get memory info: $e');
    }
  }
  
  String _formatBytes(int? bytes) {
    if (bytes == null) return '—';
    final gb = bytes / (1024 * 1024 * 1024);
    return '${gb.toStringAsFixed(1)} GB';
  }

  Future<void> _loadModelStatuses() async {
    final modelService = ref.read(modelServiceProvider);
    final statuses = <String, bool>{};
    
    for (final model in ModelService.availableModels) {
      if (model.type == ModelType.offline) {
        statuses[model.id] = await modelService.isModelDownloaded(model.id);
      } else {
        statuses[model.id] = true;
      }
    }
    
    if (mounted) {
      setState(() {
        _downloadedStatus = statuses;
        _loading = false;
      });
    }
  }

  void _listenToDownloadProgress() {
    final modelService = ref.read(modelServiceProvider);
    modelService.listenToProgress((state) {
      ref.read(modelDownloadStateProvider.notifier).state = state;
      
      if (state.status == 'completed' && state.modelId != null) {
        setState(() {
          _downloadedStatus[state.modelId!] = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _warningAnimController.dispose();
    _modelService?.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedModel = ref.watch(selectedModelProvider);
    final downloadState = ref.watch(modelDownloadStateProvider);
    const allModels = ModelService.availableModels;
    
    // Категории офлайн моделей
    final lightModels = allModels.where((m) => 
      m.type == ModelType.offline && 
      (m.id == 'llama32-1b-q8' || m.id == 'qwen25-coder-15b')
    ).toList();
    
    final universalModels = allModels.where((m) => 
      m.type == ModelType.offline && 
      (m.id == 'gemma2-2b-q5km' || m.id == 'ministral3-3b-q5km' || 
       m.id == 'llama32-3b-q5km' || m.id == 'phi35-mini-q4km')
    ).toList();
    
    final heavyModels = allModels.where((m) => 
      m.type == ModelType.offline && 
      (m.id == 'deepseek-coder-67b' || m.id == 'llama31-8b-q4km' || 
       m.id == 'saiga-yandexgpt-8b')
    ).toList();
    
    final onlineModels = allModels.where((m) => m.type == ModelType.online).toList();
    
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0a0a0f) : Colors.grey[50]!;
    final textColor = isDark ? Colors.white : Colors.black87;
    final textColorSecondary = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColorSecondary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Выбор модели',
          style: TextStyle(color: textColor, fontSize: 18),
        ),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Предупреждение
                  _buildWarning(isDark),
                  const SizedBox(height: 16),
                  // Информация о памяти
                  _buildMemoryInfo(isDark),
                  const SizedBox(height: 20),
                  
                  // Легкие модели
                  _buildCategory(
                    'Лёгкие модели',
                    Icons.bolt,
                    lightModels,
                    selectedModel,
                    downloadState,
                    isDark,
                  ),
                  const SizedBox(height: 20),
                  
                  // Универсальные модели
                  _buildCategory(
                    'Универсальные модели',
                    Icons.psychology,
                    universalModels,
                    selectedModel,
                    downloadState,
                    isDark,
                  ),
                  const SizedBox(height: 20),
                  
                  // Тяжелые модели
                  _buildCategory(
                    'Тяжёлые модели',
                    Icons.rocket_launch,
                    heavyModels,
                    selectedModel,
                    downloadState,
                    isDark,
                  ),
                  const SizedBox(height: 20),
                  
                  // Онлайн модель
                  _buildCategory(
                    'Онлайн модель',
                    Icons.cloud_outlined,
                    onlineModels,
                    selectedModel,
                    downloadState,
                    isDark,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildWarning(bool isDark) {
    if (!_showWarning) return const SizedBox.shrink();
    
    final textColor = isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black87;
    final closeIconColor = isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black45;
    
    return FadeTransition(
      opacity: _warningFadeAnim,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: isDark ? 0.1 : 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
        ),
        child: Stack(
          children: [
            // Крестик для закрытия
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showWarning = false;
                  });
                },
                child: Icon(
                  Icons.close,
                  color: closeIconColor,
                  size: 20,
                ),
              ),
            ),
            // Контент
            Column(
              children: [
                Text(
                  'ПРЕДУПРЕЖДЕНИЕ',
                  style: TextStyle(
                    color: isDark ? Colors.amber : Colors.amber[800],
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Скорость генерации зависит от модели и устройства. '
                  'Модели 6-8B параметров рекомендуются для флагманских смартфонов '
                  'с достаточным количеством RAM и мощным процессором. '
                  'Для комфортной и стабильной работы на большинстве устройств '
                  'выбирайте модели до 4B параметров.',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Кроме того, offline-модели могут ошибаться и искажать факты, '
                  'всегда проверяйте информацию. Приятной работы :)',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemoryInfo(bool isDark) {
    final labelColor = isDark ? Colors.white38 : Colors.black38;
    final iconColor = isDark ? Colors.white54 : Colors.black45;
    final textColor = isDark ? Colors.white70 : Colors.black54;
    final dividerColor = isDark ? Colors.white24 : Colors.black12;
    final bgColor = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03);
    final borderColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08);
    
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Free Storage',
                  style: TextStyle(color: labelColor, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.storage, color: iconColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${_formatBytes(_freeStorage)} / ${_formatBytes(_totalStorage)}',
                      style: TextStyle(color: textColor, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(width: 1, height: 36, color: dividerColor),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'RAM',
                  style: TextStyle(color: labelColor, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.memory, color: iconColor, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      '${_formatBytes(_freeRam)} / ${_formatBytes(_totalRam)}',
                      style: TextStyle(color: textColor, fontSize: 13),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategory(
    String title,
    IconData icon,
    List<AIModel> models,
    AIModel? selectedModel,
    ModelDownloadState downloadState,
    bool isDark,
  ) {
    final iconColor = isDark ? Colors.white54 : Colors.black45;
    final textColor = isDark ? Colors.white : Colors.black87;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                color: textColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...models.map((model) => _buildModelCard(model, selectedModel, downloadState, isDark)),
      ],
    );
  }

  Widget _buildModelCard(AIModel model, AIModel? selectedModel, ModelDownloadState downloadState, bool isDark) {
    final isSelected = selectedModel?.id == model.id;
    final isDownloaded = _downloadedStatus[model.id] ?? false;
    final isDownloading = downloadState.modelId == model.id && downloadState.status == 'downloading';
    final progress = isDownloading ? downloadState.progress : 0.0;
    
    final cardBgColor = isSelected 
        ? Colors.deepPurple.withValues(alpha: isDark ? 0.25 : 0.15) 
        : isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03);
    final borderColor = isSelected 
        ? Colors.deepPurple 
        : isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08);
    final textColor = isDownloaded || model.type == ModelType.online 
        ? (isDark ? Colors.white : Colors.black87)
        : (isDark ? Colors.white60 : Colors.black45);
    final deleteIconColor = isDark ? Colors.white30 : Colors.black26;

    return GestureDetector(
      onTap: () => _onModelTap(model, isDownloaded),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildRadio(isSelected, isDownloaded, isDownloading, isDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    model.name,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (model.type == ModelType.offline && isDownloaded && !isDownloading)
                  IconButton(
                    onPressed: () => _confirmDelete(model),
                    icon: Icon(Icons.delete_outline, color: deleteIconColor, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (model.description != null)
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  model.description!,
                  style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45,
                    fontSize: 12,
                  ),
                ),
              ),
            if (model.size != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Text(
                  model.size!,
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
            if (isDownloading) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: isDark ? Colors.white12 : Colors.black12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.deepPurple),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRadio(bool isSelected, bool isDownloaded, bool isDownloading, bool isDark) {
    if (isDownloading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
      );
    }
    
    final borderColor = isSelected 
        ? Colors.deepPurple 
        : (isDownloaded 
            ? (isDark ? Colors.white54 : Colors.black54) 
            : (isDark ? Colors.white24 : Colors.black26));
    
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor,
          width: 2,
        ),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.deepPurple,
                ),
              ),
            )
          : null,
    );
  }

  void _onModelTap(AIModel model, bool isDownloaded) {
    if (model.type == ModelType.online) {
      ref.read(selectedModelProvider.notifier).state = model;
      Navigator.of(context).pop();
      return;
    }

    if (isDownloaded) {
      ref.read(selectedModelProvider.notifier).state = model;
      Navigator.of(context).pop();
      return;
    }

    _startDownload(model);
  }

  Future<void> _startDownload(AIModel model) async {
    try {
      final modelService = ref.read(modelServiceProvider);
      await modelService.startDownload(model);
    } catch (e) {
      debugPrint('[ModelSelector] Download error: $e');
    }
  }

  void _confirmDelete(AIModel model) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a2e),
        title: const Text('Удалить модель?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Модель "${model.name}" будет удалена с устройства.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteModel(model);
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteModel(AIModel model) async {
    try {
      final phiService = ref.read(phiServiceProvider);
      await phiService.unloadModel();
      
      final modelService = ref.read(modelServiceProvider);
      final success = await modelService.deleteModel(model.id);
      
      if (success) {
        setState(() {
          _downloadedStatus[model.id] = false;
        });
        
        final selectedModel = ref.read(selectedModelProvider);
        if (selectedModel?.id == model.id) {
          final onlineModel = ModelService.availableModels.firstWhere(
            (m) => m.type == ModelType.online,
          );
          ref.read(selectedModelProvider.notifier).state = onlineModel;
        }
      }
    } catch (e) {
      debugPrint('[ModelSelector] Delete error: $e');
    }
  }
}
