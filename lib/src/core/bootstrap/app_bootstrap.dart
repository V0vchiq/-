import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/alarm/alarm_service.dart';
import '../../services/notifications/notification_service.dart';

final appBootstrapProvider = FutureProvider<void>((ref) async {
  final notifications = ref.read(notificationServiceProvider);
  final alarms = ref.read(alarmServiceProvider);
  await notifications.initialize();
  await alarms.initialize();
});
