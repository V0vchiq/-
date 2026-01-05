import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;

final calendarServiceProvider = Provider<CalendarService>((ref) {
  return CalendarService(DeviceCalendarPlugin());
});

class CalendarService {
  CalendarService(this._plugin);
  static bool _timeZonesInitialized = false;

  final DeviceCalendarPlugin _plugin;

  Future<bool> ensurePermissions() async {
    _initializeTimeZones();
    final granted = await _plugin.hasPermissions();
    if (granted.isSuccess && granted.data == true) {
      return true;
    }
    final request = await _plugin.requestPermissions();
    return request.isSuccess && request.data == true;
  }

  Future<List<Calendar>> loadCalendars() async {
    final result = await _plugin.retrieveCalendars();
    return result.data?.toList() ?? [];
  }

  Future<List<Event>> loadEvents(Calendar calendar) async {
    _initializeTimeZones();
    final now = DateTime.now();
    final end = now.add(const Duration(days: 30));
    final result = await _plugin.retrieveEvents(calendar.id!, RetrieveEventsParams(
      startDate: now,
      endDate: end,
    ));
    return result.data?.toList() ?? [];
  }

  Future<bool> addEvent(Calendar calendar, Event event) async {
    _initializeTimeZones();
    final created = await _plugin.createOrUpdateEvent(event..calendarId = calendar.id);
    return created?.isSuccess == true;
  }

  void ensureTimeZonesInitialized() => _initializeTimeZones();

  void _initializeTimeZones() {
    if (_timeZonesInitialized) return;
    tzdata.initializeTimeZones();
    _timeZonesInitialized = true;
  }
}
