import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_theme.dart';

final themeControllerProvider =
    StateNotifierProvider<ThemeController, ThemeState>((ref) {
  return ThemeController(const FlutterSecureStorage())..load();
});

class ThemeController extends StateNotifier<ThemeState> {
  ThemeController(this._storage) : super(ThemeState.initial());

  final FlutterSecureStorage _storage;

  static const _key = 'starmind_theme_mode';
  static const _skinKey = 'starmind_theme_skin';

  Future<void> load() async {
    final modeName = await _storage.read(key: _key);
    final skinName = await _storage.read(key: _skinKey);
    final mode = ThemeMode.values.firstWhere(
      (mode) => mode.name == modeName,
      orElse: () => ThemeMode.dark,
    );
    final skin = ThemeSkin.values.firstWhere(
      (skin) => skin.name == skinName,
      orElse: () => ThemeSkin.cosmos,
    );
    state = state.copyWith(mode: mode, skin: skin);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(mode: mode);
    await _storage.write(key: _key, value: mode.name);
  }

  Future<void> setThemeSkin(ThemeSkin skin) async {
    state = state.copyWith(skin: skin);
    await _storage.write(key: _skinKey, value: skin.name);
  }
}

@immutable
class ThemeState {
  const ThemeState({required this.mode, required this.skin});

  factory ThemeState.initial() =>
      const ThemeState(mode: ThemeMode.dark, skin: ThemeSkin.cosmos);

  final ThemeMode mode;
  final ThemeSkin skin;

  ThemeState copyWith({ThemeMode? mode, ThemeSkin? skin}) {
    return ThemeState(mode: mode ?? this.mode, skin: skin ?? this.skin);
  }
}

enum ThemeSkin { cosmos, dark, light }

extension ThemeSkinX on ThemeSkin {
  ThemeData get data {
    switch (this) {
      case ThemeSkin.cosmos:
        return AppTheme.cosmos;
      case ThemeSkin.dark:
        return AppTheme.dark;
      case ThemeSkin.light:
        return AppTheme.light;
    }
  }
}
