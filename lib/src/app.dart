import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/bootstrap/app_bootstrap.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class StarMindApp extends ConsumerWidget {
  const StarMindApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final theme = ref.watch(themeControllerProvider);
    final bootstrap = ref.watch(appBootstrapProvider);

    return MaterialApp.router(
      title: 'StarMind',
      themeMode: theme.mode,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        if (bootstrap.isLoading) {
          return const ColoredBox(
            color: Colors.black,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return child ?? const SizedBox.shrink();
      },
    );
  }
}
