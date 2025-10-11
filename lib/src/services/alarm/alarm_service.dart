import 'package:alarm/alarm.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final alarmServiceProvider = Provider<AlarmService>((ref) {
  return AlarmService();
});

class AlarmService {
  Future<void> initialize() async {
    await Alarm.init();
  }

  Future<void> scheduleAlarm({required DateTime when, required String title}) async {
    final alarmSettings = AlarmSettings(
      id: when.millisecondsSinceEpoch ~/ 1000,
      dateTime: when,
      assetAudioPath: 'packages/alarm/assets/alarm.mp3',
      notificationTitle: title,
      notificationBody: 'Будильник',
      loopAudio: true,
    );
    await Alarm.set(alarmSettings: alarmSettings);
  }

  Future<void> stopAlarm(int id) async {
    await Alarm.stop(id);
  }
}
