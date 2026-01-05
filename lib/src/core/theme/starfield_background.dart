import 'dart:math';
import 'package:flutter/material.dart';

class StarfieldBackground extends StatefulWidget {
  const StarfieldBackground({
    super.key,
    required this.child,
    this.isDark = true,
  });

  final Widget child;
  final bool isDark;

  @override
  State<StarfieldBackground> createState() => _StarfieldBackgroundState();
}

class _StarfieldBackgroundState extends State<StarfieldBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<_ShootingStar> _stars = [];
  final _random = Random();
  double _lastSpawnTime = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _controller.addListener(_update);
  }

  void _update() {
    final now = _controller.value + _controller.lastElapsedDuration!.inMilliseconds / 1000;
    
    // Spawn new stars periodically (every 0.3-0.8 seconds)
    if (now - _lastSpawnTime > 0.3 + _random.nextDouble() * 0.5) {
      if (_stars.length < 8) {
        _stars.add(_ShootingStar(
          x: _random.nextDouble() * 1.5 - 0.3,
          y: -0.1 - _random.nextDouble() * 0.2,
          speed: 0.8 + _random.nextDouble() * 0.6,
          length: 0.08 + _random.nextDouble() * 0.12,
          thickness: 1.0 + _random.nextDouble() * 1.5,
          opacity: 0.5 + _random.nextDouble() * 0.4,
        ));
      }
      _lastSpawnTime = now;
    }

    // Update and remove finished stars
    _stars.removeWhere((star) {
      star.progress += 0.02 * star.speed;
      return star.progress > 1.5;
    });

    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_update);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _ShootingStarPainter(
              stars: _stars,
              isDark: widget.isDark,
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _ShootingStar {
  _ShootingStar({
    required this.x,
    required this.y,
    required this.speed,
    required this.length,
    required this.thickness,
    required this.opacity,
  });

  final double x;
  final double y;
  final double speed;
  final double length;
  final double thickness;
  final double opacity;
  double progress = 0;
}

class _ShootingStarPainter extends CustomPainter {
  _ShootingStarPainter({
    required this.stars,
    required this.isDark,
  });

  final List<_ShootingStar> stars;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = isDark ? Colors.white : Colors.indigo.shade600;
    
    for (final star in stars) {
      // Diagonal movement: top-right to bottom-left
      final currentX = star.x - star.progress * 0.7;
      final currentY = star.y + star.progress * 1.2;
      
      // Trail end position
      final tailX = currentX + star.length * 0.7;
      final tailY = currentY - star.length * 1.2;
      
      final startPoint = Offset(currentX * size.width, currentY * size.height);
      final endPoint = Offset(tailX * size.width, tailY * size.height);
      
      // Gradient trail
      final gradient = LinearGradient(
        colors: [
          baseColor.withValues(alpha: star.opacity),
          baseColor.withValues(alpha: star.opacity * 0.3),
          baseColor.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.3, 1.0],
      );
      
      final paint = Paint()
        ..shader = gradient.createShader(Rect.fromPoints(startPoint, endPoint))
        ..strokeWidth = star.thickness
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      
      canvas.drawLine(startPoint, endPoint, paint);
      
      // Bright head glow
      final glowPaint = Paint()
        ..color = baseColor.withValues(alpha: star.opacity * 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(startPoint, star.thickness * 0.8, glowPaint);
      
      // Core head
      final headPaint = Paint()
        ..color = baseColor.withValues(alpha: star.opacity)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(startPoint, star.thickness * 0.5, headPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ShootingStarPainter oldDelegate) => true;
}
