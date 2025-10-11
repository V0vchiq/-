import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../calendar/presentation/calendar_screen.dart';
import '../../reminders/presentation/reminder_screen.dart';
import '../../settings/application/settings_controller.dart';
import '../../games/presentation/game_screens.dart';
import 'widgets/message_bubble.dart';
import '../application/chat_controller.dart';

class ChatShell extends ConsumerStatefulWidget {
  const ChatShell({super.key});

  static const routePath = '/chat';

  @override
  ConsumerState<ChatShell> createState() => _ChatShellState();
}

class _ChatShellState extends ConsumerState<ChatShell> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);
    final chat = ref.read(chatControllerProvider.notifier);
    final settings = ref.watch(settingsControllerProvider);
    final cosmos = Theme.of(context).extension<CosmosDecoration>();

    ref.listen(chatControllerProvider, (_, next) {
      if (_scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    });

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('StarMind', style: TextStyle(color: Colors.white70)),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CalendarScreen()),
              );
            },
            icon: const Icon(Icons.calendar_month_outlined, color: Colors.white70),
            tooltip: 'Календарь',
          ),
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ReminderScreen()),
              );
            },
            icon: const Icon(Icons.notifications_none_outlined, color: Colors.white70),
            tooltip: 'Напоминания',
          ),
          IconButton(
            onPressed: chatState.isProcessing ? null : chat.clearChat,
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.white70),
            tooltip: 'Очистить историю',
          ),
          IconButton(
            onPressed: () => _openSettings(context),
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            tooltip: 'Настройки',
          ),
        ],
      ),
      drawer: _HistoryDrawer(state: chatState, controller: chat),
      body: Container(
        decoration: cosmos != null
            ? BoxDecoration(gradient: cosmos.gradient)
            : null,
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Text(
                'Привет, что обсудим сегодня? :)',
                style: TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 0.5),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: chatState.messages.length,
                  itemBuilder: (context, index) {
                    final message = chatState.messages[index];
                    return MessageBubble(message: message);
                  },
                ),
              ),
              _InputBar(
                controller: _controller,
                state: chatState,
                onSend: () async {
                  final text = _controller.text;
                  _controller.clear();
                  await chat.sendText(text);
                },
                onVoice: () async {
                  if (chatState.isListening) {
                    await chat.stopListening(submit: true);
                  } else {
                    await chat.startListening();
                  }
                },
                onAttach: chat.ingestFile,
              ),
              const SizedBox(height: 12),
              _FooterBar(settingsState: settings, controller: chat),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black87,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return const _SettingsPanel();
      },
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.state,
    required this.onSend,
    required this.onVoice,
    required this.onAttach,
  });

  final TextEditingController controller;
  final ChatState state;
  final Future<void> Function() onSend;
  final Future<void> Function() onVoice;
  final Future<void> Function() onAttach;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 3,
              minLines: 1,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Введите вопрос...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white12,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: state.isProcessing ? null : () => onVoice(),
            icon: Icon(
              state.isListening ? Icons.stop_circle_outlined : Icons.mic_none,
              color: Colors.white70,
            ),
          ),
          IconButton(
            onPressed: state.isProcessing ? null : () => onAttach(),
            icon: const Icon(Icons.attach_file, color: Colors.white70),
          ),
          IconButton(
            onPressed: state.isProcessing ? null : () => onSend(),
            icon: state.isProcessing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _FooterBar extends ConsumerWidget {
  const _FooterBar({required this.settingsState, required this.controller});

  final SettingsState settingsState;
  final ChatController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: SwitchListTile.adaptive(
              value: settingsState.onlineMode,
              onChanged: controller.toggleOnline,
              title: const Text('Онлайн режим DeepSeek', style: TextStyle(color: Colors.white70)),
            ),
          ),
          IconButton(
            onPressed: () => _openGames(context),
            icon: const Icon(Icons.videogame_asset_outlined, color: Colors.white70),
            tooltip: 'Игры',
          ),
        ],
      ),
    );
  }

  void _openGames(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _GamesPanel(),
    );
  }
}

class _HistoryDrawer extends ConsumerWidget {
  const _HistoryDrawer({required this.state, required this.controller});

  final ChatState state;
  final ChatController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      backgroundColor: const Color(0xFF111322),
      child: SafeArea(
        child: Column(
          children: [
            const ListTile(
              title: Text('История', style: TextStyle(color: Colors.white70, fontSize: 18)),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Поиск',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: controller.searchHistory,
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final message in state.searchResults.isNotEmpty
                      ? state.searchResults
                      : state.messages)
                    ListTile(
                      title: Text(
                        message.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      subtitle: Text(
                        message.timestamp.toLocal().toString(),
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 60, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('Настройки', style: TextStyle(color: Colors.white70, fontSize: 18)),
            const SizedBox(height: 24),
          SwitchListTile.adaptive(
            value: settings.notificationsEnabled,
            onChanged: controller.setNotifications,
            title: const Text('Уведомления', style: TextStyle(color: Colors.white70)),
          ),
          SwitchListTile.adaptive(
            value: settings.calendarEnabled,
            onChanged: controller.setCalendar,
            title: const Text('Календарь', style: TextStyle(color: Colors.white70)),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Тема', style: TextStyle(color: Colors.white54)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: ThemeSkin.values
                .map(
                  (skin) => ChoiceChip(
                    label: Text(skin.name, style: const TextStyle(color: Colors.white)),
                    selected: settings.skin == skin,
                    onSelected: (_) => controller.setThemeSkin(skin),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _GamesPanel extends StatelessWidget {
  const _GamesPanel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Игры', style: TextStyle(color: Colors.white70, fontSize: 18)),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.quiz_outlined, color: Colors.white70),
            title: const Text('Trivia: История & Наука', style: TextStyle(color: Colors.white70)),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TriviaScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.text_fields, color: Colors.white70),
            title: const Text('Угадай слово', style: TextStyle(color: Colors.white70)),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuessWordScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories, color: Colors.white70),
            title: const Text('Cosmic Story Weaver', style: TextStyle(color: Colors.white70)),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StoryWeaverScreen()));
            },
          ),
        ],
      ),
    );
  }
}
