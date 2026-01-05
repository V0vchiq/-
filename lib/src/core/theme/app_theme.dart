import 'package:flutter/material.dart';

import 'theme_controller.dart';

class AppTheme {
  static const _cosmosGradient = LinearGradient(
    colors: [
      Color(0xFF080B1A),
      Color(0xFF101E3C),
      Color(0xFF1E2A4F),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigoAccent),
      scaffoldBackgroundColor: Colors.grey.shade100,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        displayColor: const Color(0xFF1a1a2e),
        bodyColor: const Color(0xFF2d2d44),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Color(0xFF1a1a2e),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: IconThemeData(color: Color(0xFF1a1a2e)),
      ),
    );
  }

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurpleAccent,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0F0F1F),
      );

  static ThemeData get cosmos {
    return dark.copyWith(
      scaffoldBackgroundColor: const Color(0xFF060910),
      extensions: const [CosmosDecoration(_cosmosGradient)],
      textTheme: dark.textTheme.apply(displayColor: Colors.white, bodyColor: Colors.white70),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class CosmosDecoration extends ThemeExtension<CosmosDecoration> {
  const CosmosDecoration(this.gradient);

  final Gradient gradient;

  @override
  ThemeExtension<CosmosDecoration> copyWith({Gradient? gradient}) {
    return CosmosDecoration(gradient ?? this.gradient);
  }

  @override
  ThemeExtension<CosmosDecoration> lerp(ThemeExtension<CosmosDecoration>? other, double t) {
    if (other is! CosmosDecoration) {
      return this;
    }
    return this;
  }
}

extension ThemeContext on BuildContext {
  ThemeData themed(ThemeSkin skin) => skin.data;

  CosmosDecoration get cosmosDecoration =>
      Theme.of(this).extension<CosmosDecoration>() ??
      const CosmosDecoration(
        LinearGradient(colors: [Colors.black, Colors.black]),
      );
}
