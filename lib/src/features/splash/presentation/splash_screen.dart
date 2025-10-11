import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_controller.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  static const routePath = '/';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final decoration = theme.extension<CosmosDecoration>() ??
        const CosmosDecoration(LinearGradient(colors: [Colors.black, Colors.black]));

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: decoration.gradient),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _TesseractIcon(),
              SizedBox(height: 24),
              Text(
                'StarMind',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Offline AI Assistant',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TesseractIcon extends StatefulWidget {
  const _TesseractIcon();

  @override
  State<_TesseractIcon> createState() => _TesseractIconState();
}

class _TesseractIconState extends State<_TesseractIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _controller.value * 6.28318,
          child: CustomPaint(
            size: const Size(96, 96),
            painter: _TesseractPainter(),
          ),
        );
      },
    );
  }
}

class _TesseractPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rectPaint = Paint()
      ..color = Colors.white.withOpacity(0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final neonPaint = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFF4BE1EC), Color(0xFF6C8CFF)],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final rect = Rect.fromLTWH(12, 12, size.width - 24, size.height - 24);
    final innerRect = Rect.fromLTWH(24, 24, size.width - 48, size.height - 48);

    canvas.drawRect(rect, rectPaint);
    canvas.drawRect(innerRect, neonPaint);

    final points = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    final innerPoints = [
      innerRect.topLeft,
      innerRect.topRight,
      innerRect.bottomRight,
      innerRect.bottomLeft,
    ];
    for (var i = 0; i < points.length; i++) {
      canvas.drawLine(points[i], innerPoints[i], neonPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
