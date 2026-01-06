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
    final skin = ThemeSkin.values.firstWhere(
      (skin) => skin.name == _prefs?.getString(_Keys.themeSkin),
      orElse: () => ThemeSkin.dark,
    );
    await ref.read(themeControllerProvider.notifier).setThemeSkin(skin);
    state = state.copyWith(
      onlineMode: online,
      skin: skin,
    );
  }

  Future<bool> setOnlineMode(bool value) async {
    if (!value) {
      final modelService = ref.read(modelServiceProvider);
      final isModelReady = await modelService.isModelDownloaded('gemma2-2b-q5km');
      if (!isModelReady) {
        return false;
      }
    }
    
    state = state.copyWith(onlineMode: value);
    await _prefs?.setBool(_Keys.onlineMode, value);
    return true;
  }

  Future<bool> isOfflineModelAvailable() async {
    final modelService = ref.read(modelServiceProvider);
    return await modelService.isModelDownloaded('gemma2-2b-q5km');
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
    required this.skin,
  });

  factory SettingsState.initial() => const SettingsState(
        onlineMode: false,
        skin: ThemeSkin.dark,
      );

  final bool onlineMode;
  final ThemeSkin skin;

  SettingsState copyWith({
    bool? onlineMode,
    ThemeSkin? skin,
  }) {
    return SettingsState(
      onlineMode: onlineMode ?? this.onlineMode,
      skin: skin ?? this.skin,
    );
  }
}

class _Keys {
  static const onlineMode = 'settings_online_mode';
  static const themeSkin = 'settings_theme_skin';
}
