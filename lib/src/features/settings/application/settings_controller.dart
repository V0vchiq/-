import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/theme_controller.dart';
import '../../../services/ai/model_service.dart';

const _deepseekKey = 'nexus_deepseek_token';

final settingsControllerProvider =
    StateNotifierProvider<SettingsController, SettingsState>((ref) {
  final controller = SettingsController(ref)..initialize();
  return controller;
});

class SettingsController extends StateNotifier<SettingsState> {
  SettingsController(this.ref) : super(SettingsState.initial());

  final Ref ref;
  SharedPreferences? _prefs;
  final _secureStorage = const FlutterSecureStorage();

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    final online = _prefs?.getBool(_Keys.onlineMode) ?? false;
    final notifications = _prefs?.getBool(_Keys.notifications) ?? true;
    final calendar = _prefs?.getBool(_Keys.calendar) ?? true;
    final skin = ThemeSkin.values.firstWhere(
      (skin) => skin.name == _prefs?.getString(_Keys.themeSkin),
      orElse: () => ThemeSkin.dark,
    );
    await ref.read(themeControllerProvider.notifier).setThemeSkin(skin);
    state = state.copyWith(
      onlineMode: online,
      notificationsEnabled: notifications,
      calendarEnabled: calendar,
      skin: skin,
    );
  }

  /// Returns true if mode was set successfully.
  /// Returns false if trying to switch to offline but model is not downloaded.
  Future<bool> setOnlineMode(bool value) async {
    // If switching to offline mode, check if model is downloaded
    if (!value) {
      final modelService = ref.read(modelServiceProvider);
      final isModelReady = await modelService.isModelDownloaded('gemma2-2b-q5km');
      if (!isModelReady) {
        return false; // Model not downloaded, cannot switch to offline
      }
    }
    
    state = state.copyWith(onlineMode: value);
    await _prefs?.setBool(_Keys.onlineMode, value);
    return true;
  }

  /// Check if offline model is available
  Future<bool> isOfflineModelAvailable() async {
    final modelService = ref.read(modelServiceProvider);
    return await modelService.isModelDownloaded('gemma2-2b-q5km');
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

  Future<void> setDeepSeekApiKey(String key) async {
    await _secureStorage.write(key: _deepseekKey, value: key);
  }

  Future<String?> getDeepSeekApiKey() async {
    return await _secureStorage.read(key: _deepseekKey);
  }

  Future<bool> hasDeepSeekApiKey() async {
    final key = await _secureStorage.read(key: _deepseekKey);
    return key != null && key.isNotEmpty;
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
        skin: ThemeSkin.dark,
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
