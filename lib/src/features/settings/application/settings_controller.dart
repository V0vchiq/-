import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/theme_controller.dart';

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  final controller = SettingsController(ref)..initialize();
  return controller;
});

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this.ref) : super(SettingsState.initial());

  final Ref ref;
  SharedPreferences? _prefs;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final online = _prefs?.getBool(_Keys.onlineMode) ?? false;
    final notifications = _prefs?.getBool(_Keys.notifications) ?? true;
    final calendar = _prefs?.getBool(_Keys.calendar) ?? true;
    final skin = ThemeSkin.values.firstWhere(
      (skin) => skin.name == _prefs?.getString(_Keys.themeSkin),
      orElse: () => ThemeSkin.cosmos,
    );
    await ref.read(themeControllerProvider.notifier).setThemeSkin(skin);
    state = state.copyWith(
      onlineMode: online,
      notificationsEnabled: notifications,
      calendarEnabled: calendar,
      skin: skin,
    );
  }

  Future<void> setOnlineMode(bool value) async {
    state = state.copyWith(onlineMode: value);
    await _prefs?.setBool(_Keys.onlineMode, value);
  }

  Future<void> setNotifications(bool value) async {
    state = state.copyWith(notificationsEnabled: value);
    await _prefs?.setBool(_Keys.notifications, value);
  }

  Future<void> setCalendar(bool value) async {
    state = state.copyWith(calendarEnabled: value);
    await _prefs?.setBool(_Keys.calendar, value);
  }

  Future<void> setThemeSkin(ThemeSkin skin) async {
    state = state.copyWith(skin: skin);
    await _prefs?.setString(_Keys.themeSkin, skin.name);
    await ref.read(themeControllerProvider.notifier).setThemeSkin(skin);
  }
}

@immutable
class SettingsState {
  const SettingsState({
    required this.onlineMode,
    required this.notificationsEnabled,
    required this.calendarEnabled,
    required this.skin,
  });

  factory SettingsState.initial() => const SettingsState(
        onlineMode: false,
        notificationsEnabled: true,
        calendarEnabled: true,
        skin: ThemeSkin.cosmos,
      );

  final bool onlineMode;
  final bool notificationsEnabled;
  final bool calendarEnabled;
  final ThemeSkin skin;

  SettingsState copyWith({
    bool? onlineMode,
    bool? notificationsEnabled,
    bool? calendarEnabled,
    ThemeSkin? skin,
  }) {
    return SettingsState(
      onlineMode: onlineMode ?? this.onlineMode,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      calendarEnabled: calendarEnabled ?? this.calendarEnabled,
      skin: skin ?? this.skin,
    );
  }
}

class _Keys {
  static const onlineMode = 'settings_online_mode';
  static const notifications = 'settings_notifications';
  static const calendar = 'settings_calendar';
  static const themeSkin = 'settings_theme_skin';
}
