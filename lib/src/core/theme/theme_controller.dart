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

  static const _key = 'nexus_theme_mode';
  static const _skinKey = 'nexus_theme_skin';

  Future<void> load() async {
    String? modeName;
    String? skinName;
    try {
      modeName = await _storage.read(key: _key);
      skinName = await _storage.read(key: _skinKey);
    } catch (_) {
      // Ignore storage errors
    }
    final mode = ThemeMode.values.firstWhere(
      (mode) => mode.name == modeName,
      orElse: () => ThemeMode.dark,
    );
    final skin = ThemeSkin.values.firstWhere(
      (skin) => skin.name == skinName,
      orElse: () => ThemeSkin.dark,
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
      const ThemeState(mode: ThemeMode.dark, skin: ThemeSkin.dark);

  final ThemeMode mode;
  final ThemeSkin skin;

  ThemeState copyWith({ThemeMode? mode, ThemeSkin? skin}) {
    return ThemeState(mode: mode ?? this.mode, skin: skin ?? this.skin);
  }
}

enum ThemeSkin { dark, light }

extension ThemeSkinX on ThemeSkin {
  ThemeData get data {
    switch (this) {
      case ThemeSkin.dark:
        return AppTheme.dark;
      case ThemeSkin.light:
        return AppTheme.light;
    }
  }
}
