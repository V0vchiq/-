import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/ai/phi_service.dart';
import '../../../services/ai/rag_service.dart';
import '../../../services/ai/online_ai_service.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/files/file_ingest_service.dart';
import '../../../services/speech/speech_service.dart';
import '../../settings/application/settings_controller.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository();
});

final chatControllerProvider =
    StateNotifierProvider<ChatController, ChatState>((ref) {
  final repo = ref.watch(chatRepositoryProvider);
  final ai = ref.watch(phiServiceProvider);
  final rag = ref.watch(ragServiceProvider);
  final speech = ref.watch(speechServiceProvider);
  final fileIngest = ref.watch(fileIngestServiceProvider);
  final settings = ref.watch(settingsControllerProvider.notifier);
  final connectivity = ref.watch(connectivityServiceProvider);
  final controller = ChatController(
    ref,
    repository: repo,
    ai: ai,
    rag: rag,
    speech: speech,
    fileIngest: fileIngest,
    settings: settings,
    connectivity: connectivity,
  );
  controller.initialize();
  return controller;
});

class ChatState {
  const ChatState({
    required this.messages,
    required this.isProcessing,
    required this.isListening,
    required this.query,
    required this.onlineEnabled,
    required this.searchResults,
  });

  factory ChatState.initial() => const ChatState(
        messages: [],
        isProcessing: false,
        isListening: false,
        query: '',
        onlineEnabled: false,
        searchResults: [],
      );

  final List<ChatMessage> messages;
  final bool isProcessing;
  final bool isListening;
  final String query;
  final bool onlineEnabled;
  final List<ChatMessage> searchResults;

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isProcessing,
    bool? isListening,
    String? query,
    bool? onlineEnabled,
    List<ChatMessage>? searchResults,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isProcessing: isProcessing ?? this.isProcessing,
      isListening: isListening ?? this.isListening,
      query: query ?? this.query,
      onlineEnabled: onlineEnabled ?? this.onlineEnabled,
      searchResults: searchResults ?? this.searchResults,
    );
  }
}

class ChatController extends StateNotifier<ChatState> {
  ChatController(
    this.ref, {
    required ChatRepository repository,
    required PhiService ai,
    required RagService rag,
    required SpeechService speech,
    required FileIngestService fileIngest,
    required SettingsController settings,
    required ConnectivityService connectivity,
  })  : _repository = repository,
        _ai = ai,
        _rag = rag,
        _speech = speech,
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
  final RagService _rag;
  final SpeechService _speech;
  final FileIngestService _fileIngest;
  final SettingsController _settings;
  final ConnectivityService _connectivity;

  StreamSubscription<String>? _speechSub;

  Future<void> initialize() async {
    _bindSettings();
    final messages = await _repository.loadMessages();
    final online = ref.read(settingsControllerProvider).onlineMode;
    state = state.copyWith(messages: messages, onlineEnabled: online);
    await _ai.ensureLoaded();
    await _rag.ensureLoaded();
  }

  Future<void> sendText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || state.isProcessing) return;
    final userMessage = ChatMessage(sender: ChatSender.user, content: trimmed);
    final updated = [...state.messages, userMessage];
    state = state.copyWith(messages: updated, isProcessing: true);
    await _repository.saveMessage(userMessage);
    final response = await _generateResponse(trimmed);
    state = state.copyWith(messages: [...updated, response], isProcessing: false);
    await _repository.saveMessage(response);
  }

  Future<void> clearChat() async {
    await _repository.clear();
    state = state.copyWith(messages: []);
  }

  Future<void> searchHistory(String query) async {
    state = state.copyWith(query: query);
    if (query.isEmpty) {
      state = state.copyWith(searchResults: []);
      return;
    }
    final results = await _repository.search(query);
    state = state.copyWith(searchResults: results);
  }

  Future<void> toggleOnline(bool value) async {
    await _settings.setOnlineMode(value);
    state = state.copyWith(onlineEnabled: value);
  }

  Future<void> startListening() async {
    if (state.isListening) return;
    final available = await _speech.initialize();
    if (!available) {
      return;
    }
    state = state.copyWith(isListening: true);
    _speechSub = _speech.onResult.listen((event) {
      state = state.copyWith(query: event);
    });
    await _speech.start();
  }

  Future<void> stopListening({bool submit = false}) async {
    if (!state.isListening) return;
    await _speech.stop();
    await _speechSub?.cancel();
    _speechSub = null;
    final text = state.query;
    state = state.copyWith(isListening: false, query: '');
    if (submit && text.isNotEmpty) {
      await sendText(text);
    }
  }

  Future<void> ingestFile() async {
    final content = await _fileIngest.pickAndRead();
    if (content == null) return;
    await sendText(content);
  }

  Future<ChatMessage> _generateResponse(String prompt) async {
    final contexts = await _rag.retrieve(prompt);
    final online = state.onlineEnabled;
    final offline = await _ai.generate(prompt, contexts: contexts);
    if (offline != null) {
      return ChatMessage(sender: ChatSender.assistant, content: offline);
    }
    if (!online) {
      return ChatMessage(sender: ChatSender.assistant, content: 'Не могу ответить оффлайн :(');
    }
    if (!await _connectivity.isOnline()) {
      return ChatMessage(sender: ChatSender.assistant, content: 'Не могу ответить оффлайн :(');
    }
    final onlineResponse = await ref.read(onlineAiServiceProvider).generate(prompt, contexts: contexts);
    return ChatMessage(
      sender: ChatSender.assistant,
      content: onlineResponse ?? 'Не могу ответить оффлайн :(',
    );
  }

  @override
  void dispose() {
    _speechSub?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
