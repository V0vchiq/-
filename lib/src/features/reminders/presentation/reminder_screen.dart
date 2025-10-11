import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/alarm/alarm_service.dart';
import '../../../services/notifications/notification_service.dart';

class ReminderScreen extends ConsumerStatefulWidget {
  const ReminderScreen({super.key});

  @override
  ConsumerState<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends ConsumerState<ReminderScreen> {
  final _titleController = TextEditingController();
  DateTime _selectedTime = DateTime.now().add(const Duration(minutes: 30));

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Напоминания & Будильник')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: Text('Время: ${_selectedTime.toLocal()}'),
              trailing: const Icon(Icons.schedule),
              onTap: _pickDateTime,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _scheduleNotification,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('Создать уведомление'),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _scheduleAlarm,
              icon: const Icon(Icons.alarm_on_outlined),
              label: const Text('Создать будильник'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedTime,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedTime),
    );
    if (time == null) return;
    setState(() {
      _selectedTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _scheduleNotification() async {
    final title = _titleController.text.trim().isEmpty ? 'StarMind напоминание' : _titleController.text.trim();
    await ref.read(notificationServiceProvider).scheduleNotification(
          id: _selectedTime.millisecondsSinceEpoch ~/ 1000,
          title: title,
          body: 'Запланированное напоминание',
          time: _selectedTime,
        );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Уведомление создано')));
    }
  }

  Future<void> _scheduleAlarm() async {
    final title = _titleController.text.trim().isEmpty ? 'StarMind будильник' : _titleController.text.trim();
    await ref.read(alarmServiceProvider).scheduleAlarm(when: _selectedTime, title: title);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Будильник создан')));
    }
  }
}
