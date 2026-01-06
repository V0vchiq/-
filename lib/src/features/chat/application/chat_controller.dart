import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/ai/phi_service.dart';
import '../../../services/ai/online_ai_service.dart';
import '../../../services/ai/model_service.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/files/file_ingest_service.dart';
import '../../settings/application/settings_controller.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';
import '../domain/chat_session.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repo = ChatRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});

final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  final ai = ref.watch(phiServiceProvider);
  final fileIngest = ref.watch(fileIngestServiceProvider);
  final settings = ref.watch(settingsControllerProvider.notifier);
  final connectivity = ref.watch(connectivityServiceProvider);
  final controller = ChatController(
    ref,
    repository: repo,
    ai: ai,
    fileIngest: fileIngest,
    settings: settings,
    connectivity: connectivity,
  );
  controller.initialize();
  return controller;
});

class AttachedFile {
  final String name;
  final String path;
  final String? content;
  final bool isSupported;
  
  const AttachedFile({
    required this.name,
    required this.path,
    this.content,
    this.isSupported = true,
  });
}

class ChatState {
  const ChatState({
    required this.messages,
    required this.isProcessing,
    required this.onlineEnabled,
    required this.searchResults,
    required this.modelDownloadProgress,
    required this.sessions,
    required this.currentSession,
    this.attachedFile,
  });

  factory ChatState.initial() => const ChatState(
        messages: [],
        isProcessing: false,
        onlineEnabled: false,
        searchResults: [],
        modelDownloadProgress: null,
        sessions: [],
        currentSession: null,
        attachedFile: null,
      );

  final List<ChatMessage> messages;
  final bool isProcessing;
  final bool onlineEnabled;
  final List<ChatMessage> searchResults;
  final double? modelDownloadProgress;
  final List<ChatSession> sessions;
  final ChatSession? currentSession;
  final AttachedFile? attachedFile;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isProcessing,
    bool? onlineEnabled,
    List<ChatMessage>? searchResults,
    double? Function()? modelDownloadProgress,
    List<ChatSession>? sessions,
    ChatSession? Function()? currentSession,
    AttachedFile? Function()? attachedFile,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isProcessing: isProcessing ?? this.isProcessing,
      onlineEnabled: onlineEnabled ?? this.onlineEnabled,
      searchResults: searchResults ?? this.searchResults,
      modelDownloadProgress: modelDownloadProgress != null
          ? modelDownloadProgress()
          : this.modelDownloadProgress,
      sessions: sessions ?? this.sessions,
      currentSession: currentSession != null
          ? currentSession()
          : this.currentSession,
      attachedFile: attachedFile != null
          ? attachedFile()
          : this.attachedFile,
    );
  }
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(
    this.ref, {
    required ChatRepository repository,
    required PhiService ai,
    required FileIngestService fileIngest,
    required SettingsController settings,
    required ConnectivityService connectivity,
  })  : _repository = repository,
        _ai = ai,
        _fileIngest = fileIngest,
        _settings = settings,
        _connectivity = connectivity,
        super(ChatState.initial());

  void _bindSettings() {
    ref.listen<SettingsState>(settingsControllerProvider, (previous, next) {
      state = state.copyWith(onlineEnabled: next.onlineMode);
    });
  }

  final Ref ref;
  final ChatRepository _repository;
  final PhiService _ai;
  final FileIngestService _fileIngest;
  final SettingsController _settings;
  final ConnectivityService _connectivity;

  bool _isCancelled = false;
  DateTime _lastUiUpdate = DateTime.now();
  static const _uiThrottleMs = 50; // Обновлять UI не чаще чем раз в 50мс

  Future<void> initialize() async {
    _bindSettings();
    final online = ref.read(settingsControllerProvider).onlineMode;
    
    try {
      final sessions = await _repository.loadSessions();
      
      if (sessions.isEmpty) {
        // Create first session
        final session = await _repository.createSession('Новый чат');
        state = state.copyWith(
          sessions: [session],
          currentSession: () => session,
          messages: [],
          onlineEnabled: online,
        );
      } else {
        // Load most recent session
        final currentSession = sessions.first;
        final messages = await _repository.loadMessages(sessionId: currentSession.id);
        state = state.copyWith(
          sessions: sessions,
          currentSession: () => currentSession,
          messages: messages,
          onlineEnabled: online,
        );
      }
    } catch (e) {
      debugPrint('[Nexus] Initialize error: $e');
      // Fallback - работаем без сессий
      state = state.copyWith(
        messages: [],
        onlineEnabled: online,
      );
    }
  }

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    final attached = state.attachedFile;
    
    if (trimmed.isEmpty && attached == null) return;
    if (state.isProcessing) return;
    
    // Если файл не поддерживается - показываем предупреждение
    if (attached != null && !attached.isSupported) {
      state = state.copyWith(attachedFile: () => null);
      final warningMessage = ChatMessage(
        sender: ChatSender.assistant, 
        content: 'Формат файла "${attached.name}" не поддерживается. Поддерживаются только текстовые файлы (txt, md, json, csv, xml, html, css, js, dart, py и др.)',
      );
      state = state.copyWith(messages: [...state.messages, warningMessage]);
      return;
    }
    
    final sessionId = state.currentSession?.id;
    final isFirstMessage = state.messages.isEmpty;
    
    _isCancelled = false;
    
    // Формируем сообщение пользователя
    String displayText = trimmed;
    if (attached != null) {
      displayText = trimmed.isEmpty 
          ? '[Файл: ${attached.name}]'
          : '$trimmed\n[Файл: ${attached.name}]';
    }
    
    // Формируем промпт для модели (с содержимым файла)
    String promptForModel = trimmed;
    if (attached != null && attached.content != null) {
      promptForModel = trimmed.isEmpty
          ? 'Содержимое файла "${attached.name}":\n${attached.content}'
          : '$trimmed\n\nСодержимое файла "${attached.name}":\n${attached.content}';
    }
    
    final userMessage = ChatMessage(sender: ChatSender.user, content: displayText);
    final updated = [...state.messages, userMessage];
    state = state.copyWith(
      messages: updated, 
      isProcessing: true,
      attachedFile: () => null,
    );
    await _repository.saveMessage(userMessage, sessionId: sessionId);
    
    // Определяем режим по выбранной модели
    final selectedModel = ref.read(selectedModelProvider);
    final isOnlineModel = selectedModel?.type == ModelType.online;
    
    bool hasInternet = false;
    try {
      hasInternet = await _connectivity.isOnline();
    } catch (_) {}
    
    ChatMessage response;
    
    if (isOnlineModel && hasInternet) {
      // Онлайн режим со стримингом
      response = await _generateResponseOnlineWithStreaming(promptForModel, updated);
    } else if (!isOnlineModel || !hasInternet) {
      // Офлайн режим со стримингом
      response = await _generateResponseWithStreaming(promptForModel, updated);
    } else {
      // Fallback - офлайн
      response = await _generateResponseWithStreaming(promptForModel, updated);
    }
    
    if (_isCancelled) {
      state = state.copyWith(isProcessing: false);
      return;
    }
    
    // Финальное обновление state
    final finalMessages = [...updated, response];
    state = state.copyWith(messages: finalMessages, isProcessing: false);
    await _repository.saveMessage(response, sessionId: sessionId);
    
    // Generate title after first message
    if (isFirstMessage && sessionId != null) {
      _generateSessionTitle(trimmed, sessionId);
    }
  }

  Future<ChatMessage> _generateResponseWithStreaming(String prompt, List<ChatMessage> currentMessages) async {
    debugPrint('[Nexus] Using offline model with streaming...');
    
    final buffer = StringBuffer();
    var assistantMessage = ChatMessage(sender: ChatSender.assistant, content: '');
    
    // Добавляем пустое сообщение ассистента
    state = state.copyWith(messages: [...currentMessages, assistantMessage]);
    _lastUiUpdate = DateTime.now();
    
    try {
      // История диалога (последние 2 сообщения для офлайн, лимит 2000 символов)
      final history = _buildHistory(currentMessages, maxMessages: 2, maxChars: 2000);
      final fullPrompt = _ai.buildPromptForStreaming(prompt, history: history);
      
      await for (final token in _ai.generateStream(fullPrompt)) {
        if (_isCancelled) break;
        
        buffer.write(token);
        final currentText = buffer.toString();
        
        // Проверяем стоп-токены во время генерации
        if (_containsStopToken(currentText)) {
          _ai.stopGeneration();
          break;
        }
        
        // Throttle: обновляем UI не чаще чем раз в _uiThrottleMs
        final now = DateTime.now();
        if (now.difference(_lastUiUpdate).inMilliseconds >= _uiThrottleMs) {
          assistantMessage = ChatMessage(
            sender: ChatSender.assistant, 
            content: _ai.sanitizeResponse(currentText) ?? '',
          );
          state = state.copyWith(messages: [...currentMessages, assistantMessage]);
          _lastUiUpdate = now;
        }
      }
      
      final finalContent = _ai.sanitizeResponse(buffer.toString());
      return ChatMessage(
        sender: ChatSender.assistant, 
        content: finalContent ?? 'Не удалось получить ответ',
      );
    } catch (e) {
      debugPrint('[Nexus] Streaming error: $e');
      return ChatMessage(
        sender: ChatSender.assistant, 
        content: 'Ошибка генерации. Попробуйте ещё раз.',
      );
    }
  }
  
  Future<ChatMessage> _generateResponseOnlineWithStreaming(String prompt, List<ChatMessage> currentMessages) async {
    debugPrint('[Nexus] Using online API with streaming...');
    
    final buffer = StringBuffer();
    var assistantMessage = ChatMessage(sender: ChatSender.assistant, content: '');
    
    state = state.copyWith(messages: [...currentMessages, assistantMessage]);
    _lastUiUpdate = DateTime.now();
    
    try {
      // История диалога (последние 5 сообщений для онлайн)
      final history = _buildHistory(currentMessages, maxMessages: 5, maxChars: 6000);
      final onlineService = ref.read(onlineAiServiceProvider);
      
      await for (final token in onlineService.generateStream(prompt, history: history)) {
        if (_isCancelled) break;
        
        buffer.write(token);
        
        // Throttle: обновляем UI не чаще чем раз в _uiThrottleMs
        final now = DateTime.now();
        if (now.difference(_lastUiUpdate).inMilliseconds >= _uiThrottleMs) {
          assistantMessage = ChatMessage(
            sender: ChatSender.assistant, 
            content: buffer.toString(),
          );
          state = state.copyWith(messages: [...currentMessages, assistantMessage]);
          _lastUiUpdate = now;
        }
      }
      
      final content = buffer.toString().trim();
      return ChatMessage(
        sender: ChatSender.assistant, 
        content: content.isEmpty ? 'Не удалось получить ответ' : content,
      );
    } catch (e) {
      debugPrint('[Nexus] Online streaming error: $e');
      return ChatMessage(
        sender: ChatSender.assistant, 
        content: 'Ошибка подключения к серверу.',
      );
    }
  }

  List<Map<String, String>> _buildHistory(List<ChatMessage> messages, {int maxMessages = 6, int maxChars = 8000}) {
    // Исключаем последнее сообщение (текущий вопрос - он добавляется отдельно)
    if (messages.isEmpty) return [];
    final withoutCurrent = messages.sublist(0, messages.length - 1);
    
    // Берём последние N сообщений
    var recent = withoutCurrent.length > maxMessages 
        ? withoutCurrent.sublist(withoutCurrent.length - maxMessages) 
        : withoutCurrent;
    
    // Ограничиваем по длине (примерно 4 символа = 1 токен, оставляем запас для ответа)
    int totalChars = recent.fold(0, (sum, msg) => sum + msg.content.length);
    while (totalChars > maxChars && recent.length > 1) {
      recent = recent.sublist(1); // Убираем самое старое сообщение
      totalChars = recent.fold(0, (sum, msg) => sum + msg.content.length);
    }
    
    return recent.map((msg) => {
      'role': msg.sender == ChatSender.user ? 'user' : 'assistant',
      'content': msg.content,
    }).toList();
  }
  
  /// Проверяет наличие стоп-токенов в тексте
  bool _containsStopToken(String text) {
    const stopTokens = [
      'Пользователь:',
      'Ты — русскоязычный',
      '<|eot_id|>',
      '<|start_header_id|>',
      '<|im_end|>',
      '<|im_start|>',
      '<|end|>',
      '<|user|>',
      '<|endoftext|>',
      '</s>',
      '[INST]',
      '<end_of_turn>',
      '<start_of_turn>',
    ];
    for (final token in stopTokens) {
      if (text.contains(token)) return true;
    }
    return false;
  }
  
  Future<void> _generateSessionTitle(String firstMessage, String sessionId) async {
    try {
      final prompt = 'Дай очень краткое название темы (2-4 слова) для этого вопроса, без кавычек и пояснений: $firstMessage';
      String? titleResult;
      
      if (state.onlineEnabled) {
        final onlineService = ref.read(onlineAiServiceProvider);
        titleResult = await onlineService.generate(prompt);
      } else {
        titleResult = await _ai.generate(prompt);
      }
      
      if (titleResult == null || titleResult.isEmpty) return;
      
      // Clean up title
      var title = titleResult.trim().replaceAll('"', '').replaceAll('«', '').replaceAll('»', '');
      if (title.length > 50) title = title.substring(0, 50);
      if (title.isEmpty) title = 'Чат';
      
      await _repository.updateSessionTitle(sessionId, title);
      
      // Update session in state
      final updatedSessions = state.sessions.map((s) {
        if (s.id == sessionId) {
          return s.copyWith(title: title);
        }
        return s;
      }).toList();
      
      final updatedCurrent = state.currentSession?.id == sessionId
          ? state.currentSession?.copyWith(title: title)
          : state.currentSession;
      
      state = state.copyWith(
        sessions: updatedSessions,
        currentSession: () => updatedCurrent,
      );
    } catch (e) {
      // Ignore title generation errors
    }
  }

  void cancelGeneration() {
    if (!state.isProcessing) return;
    _isCancelled = true;
    
    final selectedModel = ref.read(selectedModelProvider);
    if (selectedModel?.type == ModelType.online) {
      // Отменяем HTTP запрос для онлайн модели
      ref.read(onlineAiServiceProvider).cancelStream();
    } else {
      // Останавливаем нативную генерацию для офлайн модели
      _ai.stopGeneration();
    }
    
    state = state.copyWith(isProcessing: false);
  }

  Future<void> clearChat() async {
    final sessionId = state.currentSession?.id;
    if (sessionId != null) {
      await _repository.clearSession(sessionId);
    }
    state = state.copyWith(messages: []);
  }

  Future<void> newChat() async {
    final session = await _repository.createSession('Новый чат');
    final sessions = [session, ...state.sessions];
    state = state.copyWith(
      sessions: sessions,
      currentSession: () => session,
      messages: [],
    );
  }

  Future<void> switchSession(ChatSession session) async {
    if (session.id == state.currentSession?.id) return;
    final messages = await _repository.loadMessages(sessionId: session.id);
    state = state.copyWith(
      currentSession: () => session,
      messages: messages,
    );
  }

  Future<void> deleteSession(String sessionId) async {
    await _repository.deleteSession(sessionId);
    final sessions = state.sessions.where((s) => s.id != sessionId).toList();
    
    if (state.currentSession?.id == sessionId) {
      if (sessions.isNotEmpty) {
        final newCurrent = sessions.first;
        final messages = await _repository.loadMessages(sessionId: newCurrent.id);
        state = state.copyWith(
          sessions: sessions,
          currentSession: () => newCurrent,
          messages: messages,
        );
      } else {
        // Create new session if all deleted
        final newSession = await _repository.createSession('Новый чат');
        state = state.copyWith(
          sessions: [newSession],
          currentSession: () => newSession,
          messages: [],
        );
      }
    } else {
      state = state.copyWith(sessions: sessions);
    }
  }

  Future<void> searchHistory(String query) async {
    if (query.isEmpty) {
      state = state.copyWith(searchResults: []);
      return;
    }
    final results = await _repository.search(query);
    state = state.copyWith(searchResults: results);
  }

  /// Returns true if mode was toggled successfully.
  /// Returns false if trying to switch to offline but model is not downloaded.
  Future<bool> toggleOnline(bool value) async {
    final success = await _settings.setOnlineMode(value);
    if (success) {
      state = state.copyWith(onlineEnabled: value);
    }
    return success;
  }

  /// Check if offline model is available
  Future<bool> isOfflineModelAvailable() async {
    return await _settings.isOfflineModelAvailable();
  }

  Future<void> ingestFile() async {
    final picked = await _fileIngest.pickFile();
    if (picked == null) return;
    
    state = state.copyWith(
      attachedFile: () => AttachedFile(
        name: picked.name,
        path: picked.path,
        content: picked.content,
        isSupported: picked.isSupported,
      ),
    );
  }
  
  void removeAttachedFile() {
    state = state.copyWith(attachedFile: () => null);
  }

  @override
  void dispose() {
    _repository.dispose();
    super.dispose();
  }
}
