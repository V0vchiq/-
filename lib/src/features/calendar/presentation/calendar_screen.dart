import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../services/calendar/calendar_service.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  Calendar? _calendar;
  List<Event> _events = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = ref.read(calendarServiceProvider);
    final hasAccess = await service.ensurePermissions();
    if (!hasAccess) {
      setState(() => _loading = false);
      return;
    }
    final calendars = await service.loadCalendars();
    final calendar = calendars.isNotEmpty ? calendars.first : null;
    if (calendar != null) {
      final events = await service.loadEvents(calendar);
      setState(() {
        _calendar = calendar;
        _events = events;
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Календарь')),
      floatingActionButton: FloatingActionButton(
        onPressed: _calendar == null ? null : _addEvent,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _calendar == null
              ? const Center(child: Text('Календарь не найден'))
              : ListView.builder(
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return ListTile(
                      leading: const Icon(Icons.event),
                      title: Text(event.title ?? 'Событие'),
                      subtitle: Text(event.start?.toLocal().toString() ?? ''),
                    );
                  },
                ),
    );
  }

  Future<void> _addEvent() async {
    final service = ref.read(calendarServiceProvider);
    final calendar = _calendar;
    if (calendar == null) return;
    service.ensureTimeZonesInitialized();
    final now = DateTime.now().add(const Duration(hours: 1));
    final tzNow = tz.TZDateTime.from(now, tz.local);
    final success = await service.addEvent(
      calendar,
      Event(
        calendar.id,
        title: 'Nexus напоминание',
        start: tzNow,
        end: tzNow.add(const Duration(minutes: 30)),
      ),
    );
    if (success) {
      await _load();
    }
  }
}
