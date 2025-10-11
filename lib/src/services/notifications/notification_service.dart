import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(FlutterLocalNotificationsPlugin());
});

class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> initialize() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    tz.initializeTimeZones();
  }

  Future<void> scheduleNotification({required int id, required String title, required String body, required DateTime time}) async {
    final android = AndroidNotificationDetails(
      'starmind_notifications',
      'StarMind Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: android);
    final scheduled = tz.TZDateTime.from(time, tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dateAndTime,
    );
  }

  Future<void> cancel(int id) async {
    await _plugin.cancel(id);
  }
}
