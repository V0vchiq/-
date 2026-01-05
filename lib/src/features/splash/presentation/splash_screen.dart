import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../chat/presentation/chat_shell.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  static const routePath = '/';

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isFirstLaunch = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _startIntroSequence();
  }

  Future<void> _startIntroSequence() async {
    final prefs = await SharedPreferences.getInstance();
    _isFirstLaunch = prefs.getBool('first_launch_completed') != true;

    if (_isFirstLaunch) {
      await _runFirstLaunchIntro();
      await prefs.setBool('first_launch_completed', true);
    } else {
      await _runQuickSplash();
    }
    
    _navigateNext();
  }

  Future<void> _runFirstLaunchIntro() async {
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await _fadeController.forward();
    await Future.delayed(const Duration(milliseconds: 3000));
    if (!mounted) return;
    await _fadeController.reverse();
  }

  Future<void> _runQuickSplash() async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    await _fadeController.forward();
    await Future.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    await _fadeController.reverse();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _navigateNext() {
    if (!mounted) return;
    context.go(ChatShell.routePath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final decoration = theme.extension<CosmosDecoration>() ??
        const CosmosDecoration(
            LinearGradient(colors: [Colors.black, Colors.black]));

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: decoration.gradient),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'NEXUS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                    ),
                  ),
                  const SizedBox(height: 48),
                  _AnimatedIcon(size: _isFirstLaunch ? 240 : 192),
                  const SizedBox(height: 24),
                  const Text(
                    'AI Assistant',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedIcon extends StatefulWidget {
  const _AnimatedIcon({this.size = 192});

  final double size;

  @override
  State<_AnimatedIcon> createState() => _AnimatedIconState();
}

class _AnimatedIconState extends State<_AnimatedIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.size * 0.2),
            child: Image.asset(
              'assets/images/app_icon.png',
              width: widget.size,
              height: widget.size,
            ),
          ),
        );
      },
    );
  }
}
