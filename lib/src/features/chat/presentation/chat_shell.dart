// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/starfield_background.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../services/ai/model_service.dart';
import '../../settings/application/settings_controller.dart';
import 'widgets/message_bubble.dart';
import 'screens/model_selector_screen.dart';
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
  bool _isAtBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    // Считаем "внизу" если до конца меньше 100 пикселей
    _isAtBottom = (maxScroll - currentScroll) < 100;
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatControllerProvider);
    final chat = ref.read(chatControllerProvider.notifier);
    final settings = ref.watch(settingsControllerProvider);

    ref.listen(chatControllerProvider, (_, next) {
      // Автопрокрутка только если пользователь внизу
      if (_scrollController.hasClients && _isAtBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    });

    final isDark = settings.skin == ThemeSkin.dark;
    final iconColor = isDark ? Colors.white70 : const Color(0xFF1a1a2e);
    final titleColor = isDark ? Colors.white70 : const Color(0xFF1a1a2e);

    final selectedModel = ref.watch(selectedModelProvider);
    final modelName = selectedModel?.name ?? 'Выбрать модель';
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: GestureDetector(
          onTap: () => _openModelSelector(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(modelName, style: TextStyle(color: titleColor, fontSize: 16)),
              const SizedBox(width: 4),
              Icon(Icons.arrow_drop_down, color: iconColor, size: 20),
            ],
          ),
        ),
        iconTheme: IconThemeData(color: iconColor),
        actions: [
          IconButton(
            onPressed: chatState.isProcessing ? null : chat.clearChat,
            icon: Icon(Icons.delete_sweep_outlined, color: iconColor),
            tooltip: 'Очистить историю',
          ),
          IconButton(
            onPressed: () => _openSettings(context),
            icon: Icon(Icons.settings_outlined, color: iconColor),
            tooltip: 'Настройки',
          ),
        ],
      ),
      drawer: _HistoryDrawer(state: chatState, controller: chat),
      body: StarfieldBackground(
        isDark: settings.skin == ThemeSkin.dark,
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: chatState.messages.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _ChatHeader(progress: chatState.modelDownloadProgress);
                    }
                    final message = chatState.messages[index - 1];
                    return MessageBubble(message: message);
                  },
                ),
              ),
              _InputBar(
                controller: _controller,
                state: chatState,
                isDark: isDark,
                onSend: () async {
                  final text = _controller.text;
                  _controller.clear();
                  await chat.sendText(text);
                },
                onAttach: chat.ingestFile,
                onRemoveAttachment: chat.removeAttachedFile,
                onCancel: chat.cancelGeneration,
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return const _SettingsPanel();
      },
    );
  }

  void _openModelSelector(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const ModelSelectorScreen(),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.state,
    required this.onSend,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onCancel,
    required this.isDark,
  });

  final TextEditingController controller;
  final ChatState state;
  final Future<void> Function() onSend;
  final Future<void> Function() onAttach;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onCancel;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF1a1a2e);
    final hintColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08);
    final iconColor = isDark ? Colors.white70 : const Color(0xFF1a1a2e);
    final attached = state.attachedFile;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (attached != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: attached.isSupported 
                    ? (isDark ? Colors.blue.withValues(alpha: 0.3) : Colors.blue.withValues(alpha: 0.15))
                    : (isDark ? Colors.orange.withValues(alpha: 0.3) : Colors.orange.withValues(alpha: 0.15)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    attached.isSupported ? Icons.description : Icons.warning_amber,
                    size: 16,
                    color: attached.isSupported ? Colors.blue : Colors.orange,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      attached.name,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onRemoveAttachment,
                    child: Icon(Icons.close, size: 16, color: iconColor),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: 3,
                  minLines: 1,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  enableIMEPersonalizedLearning: true,
                  autocorrect: true,
                  enableSuggestions: true,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: attached != null ? 'Добавьте вопрос к файлу...' : 'Введите вопрос...',
                    hintStyle: TextStyle(color: hintColor),
                    filled: true,
                    fillColor: fillColor,
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
                onPressed: state.isProcessing ? null : () => onAttach(),
                icon: Icon(Icons.attach_file, color: iconColor),
              ),
              IconButton(
                onPressed: state.isProcessing ? onCancel : () => onSend(),
                icon: state.isProcessing
                    ? const Icon(Icons.stop_circle_outlined, color: Colors.redAccent, size: 28)
                    : Icon(Icons.send_rounded, color: iconColor),
              ),
            ],
          ),
        ],
      ),
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
            ListTile(
              title: const Text('История чатов', style: TextStyle(color: Colors.white70, fontSize: 18)),
              trailing: IconButton(
                icon: const Icon(Icons.add, color: Colors.white70),
                onPressed: () {
                  controller.newChat();
                  Navigator.pop(context);
                },
                tooltip: 'Новый чат',
              ),
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: ListView.builder(
                itemCount: state.sessions.length,
                itemBuilder: (context, index) {
                  final session = state.sessions[index];
                  final isSelected = session.id == state.currentSession?.id;
                  return Dismissible(
                    key: Key(session.id),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 16),
                      color: Colors.red.shade900,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (_) async {
                      return await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1a1a2e),
                          title: const Text('Удалить чат?', style: TextStyle(color: Colors.white70)),
                          content: Text('Чат "${session.title}" будет удалён', style: const TextStyle(color: Colors.white54)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Удалить', style: TextStyle(color: Colors.red))),
                          ],
                        ),
                      ) ?? false;
                    },
                    onDismissed: (_) => controller.deleteSession(session.id),
                    child: ListTile(
                      selected: isSelected,
                      selectedTileColor: Colors.white.withValues(alpha: 0.1),
                      leading: CircleAvatar(
                        backgroundColor: isSelected ? Colors.deepPurple : Colors.white12,
                        radius: 16,
                        child: Text(
                          '${session.number}',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        _formatDate(session.createdAt),
                        style: const TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                      onTap: () {
                        controller.switchSession(session);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year;
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }
}

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final controller = ref.read(settingsControllerProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final bgColor = isDark ? Colors.black87 : Colors.white;
    final handleColor = isDark ? Colors.white24 : Colors.black26;
    final titleColor = isDark ? Colors.white70 : Colors.black87;
    final labelColor = isDark ? Colors.white54 : Colors.black54;
    final chipBgColor = isDark ? Colors.white24 : Colors.black12;
    final chipTextColor = isDark ? Colors.white70 : Colors.black54;
    
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 60, height: 4, decoration: BoxDecoration(color: handleColor, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Настройки', style: TextStyle(color: titleColor, fontSize: 18)),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Тема', style: TextStyle(color: labelColor)),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: ThemeSkin.values
                .map(
                  (skin) => ChoiceChip(
                    label: Text(
                      skin.name == 'dark' ? 'Тёмная' : 'Светлая',
                      style: TextStyle(
                        color: settings.skin == skin ? Colors.white : chipTextColor,
                      ),
                    ),
                    selected: settings.skin == skin,
                    selectedColor: Colors.deepPurple,
                    backgroundColor: chipBgColor,
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

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({required this.progress});

  final double? progress;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).textTheme.bodyMedium?.color ?? Colors.white54;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 4),
        Text(
          'Привет, что обсудим сегодня? :)',
          style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 16, letterSpacing: 0.5),
        ),
        const SizedBox(height: 12),
        if (progress != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
            child: _ModelDownloadBanner(progress: progress!),
          ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _ModelDownloadBanner extends StatelessWidget {
  const _ModelDownloadBanner({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final double clamped = progress.clamp(0.0, 1.0);
    final bool determinate = clamped > 0 && clamped < 0.999;
    final int percent = (clamped * 100).clamp(0, 100).round();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: determinate
                ? CircularProgressIndicator(
                    value: clamped,
                    strokeWidth: 3,
                    color: Colors.white70,
                  )
                : const CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white70,
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Загружаем офлайн-модель…',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  determinate ? '$percent%' : 'Это займёт пару минут, не закрывайте приложение',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

