import 'dart:math';
import 'package:flutter/material.dart';

class NeuralBrainWidget extends StatefulWidget {
  const NeuralBrainWidget({super.key, this.size = 192});

  final double size;

  @override
  State<NeuralBrainWidget> createState() => _NeuralBrainWidgetState();
}

class _NeuralBrainWidgetState extends State<NeuralBrainWidget>
    with TickerProviderStateMixin {
  late AnimationController _assembleController;
  late AnimationController _pulseController;
  late AnimationController _signalController;
  late Animation<double> _assembleAnimation;
  late Animation<double> _pulseAnimation;
  
  // Рандомные точки генерируются один раз
  late List<Offset> _startNodes;
  late List<Offset> _endNodes;
  late List<List<int>> _connections;

  @override
  void initState() {
    super.initState();
    
    // Генерируем рандомную нейросеть
    _generateRandomNetwork();
    
    // Анимация сборки - точки летят к центру
    _assembleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _assembleAnimation = CurvedAnimation(
      parent: _assembleController,
      curve: Curves.easeOutCubic,
    );
    _assembleController.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _signalController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }
  
  void _generateRandomNetwork() {
    final random = Random();
    final nodeCount = 18 + random.nextInt(8); // 18-25 нейронов
    
    _startNodes = [];
    _endNodes = [];
    _connections = [];
    
    // Генерируем начальные позиции (за пределами экрана)
    for (int i = 0; i < nodeCount; i++) {
      final side = random.nextInt(4);
      late Offset start;
      switch (side) {
        case 0: // сверху
          start = Offset(random.nextDouble(), -0.1 - random.nextDouble() * 0.3);
          break;
        case 1: // справа
          start = Offset(1.1 + random.nextDouble() * 0.3, random.nextDouble());
          break;
        case 2: // снизу
          start = Offset(random.nextDouble(), 1.1 + random.nextDouble() * 0.3);
          break;
        default: // слева
          start = Offset(-0.1 - random.nextDouble() * 0.3, random.nextDouble());
      }
      _startNodes.add(start);
    }
    
    // Генерируем конечные позиции (в центральной области)
    for (int i = 0; i < nodeCount; i++) {
      // Распределяем точки по кольцам
      final ring = i % 3;
      final angle = (i / nodeCount) * 2 * pi + random.nextDouble() * 0.5;
      final radius = switch (ring) {
        0 => 0.1 + random.nextDouble() * 0.1,  // центр
        1 => 0.2 + random.nextDouble() * 0.1,  // среднее кольцо
        _ => 0.3 + random.nextDouble() * 0.1,  // внешнее кольцо
      };
      
      final x = 0.5 + cos(angle) * radius;
      final y = 0.5 + sin(angle) * radius;
      _endNodes.add(Offset(x, y));
    }
    
    // Генерируем связи на основе расстояния
    for (int i = 0; i < nodeCount; i++) {
      for (int j = i + 1; j < nodeCount; j++) {
        final dist = (_endNodes[i] - _endNodes[j]).distance;
        // Соединяем близкие точки с вероятностью
        if (dist < 0.25 && random.nextDouble() < 0.6) {
          _connections.add([i, j]);
        }
      }
    }
    
    // Гарантируем минимум связей
    if (_connections.length < 15) {
      for (int i = 0; i < nodeCount - 1 && _connections.length < 20; i++) {
        if (!_connections.any((c) => (c[0] == i && c[1] == i + 1) || (c[0] == i + 1 && c[1] == i))) {
          _connections.add([i, i + 1]);
        }
      }
    }
  }

  @override
  void dispose() {
    _assembleController.dispose();
    _pulseController.dispose();
    _signalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_assembleController, _pulseController, _signalController]),
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _NeuralBrainPainter(
            assembleValue: _assembleAnimation.value,
            pulseValue: _pulseAnimation.value,
            signalValue: _signalController.value,
            startNodes: _startNodes,
            endNodes: _endNodes,
            connections: _connections,
          ),
        );
      },
    );
  }
}

class _NeuralBrainPainter extends CustomPainter {
  _NeuralBrainPainter({
    required this.assembleValue,
    required this.pulseValue,
    required this.signalValue,
    required this.startNodes,
    required this.endNodes,
    required this.connections,
  });

  final double assembleValue;
  final double pulseValue;
  final double signalValue;
  final List<Offset> startNodes;
  final List<Offset> endNodes;
  final List<List<int>> connections;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final lineOpacity = (assembleValue - 0.3).clamp(0.0, 1.0) / 0.7;

    // Вычисляем текущие позиции
    final List<Offset> currentNodes = [];
    for (int i = 0; i < endNodes.length; i++) {
      final current = Offset.lerp(startNodes[i], endNodes[i], assembleValue)!;
      currentNodes.add(current.multiply(s));
    }

    // Рисуем связи (появляются постепенно)
    if (lineOpacity > 0) {
      for (int i = 0; i < connections.length; i++) {
        final conn = connections[i];
        if (conn[0] >= currentNodes.length || conn[1] >= currentNodes.length) continue;
        
        final start = currentNodes[conn[0]];
        final end = currentNodes[conn[1]];

        final linePaint = Paint()
          ..color = Colors.purpleAccent.withValues(alpha: 0.5 * lineOpacity * pulseValue)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;

        canvas.drawLine(start, end, linePaint);

        // Импульсы по линиям
        if (assembleValue > 0.8) {
          final signalIndex = (signalValue * connections.length).floor();
          if (i == signalIndex || i == (signalIndex + 7) % connections.length ||
              i == (signalIndex + 14) % connections.length) {
            final progress = (signalValue * 3) % 1.0;
            final signalPos = Offset.lerp(start, end, progress)!;

            final signalPaint = Paint()
              ..color = Colors.cyanAccent.withValues(alpha: 0.9)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

            canvas.drawCircle(signalPos, 4, signalPaint);
          }
        }
      }
    }

    // Рисуем нейроны
    for (int i = 0; i < currentNodes.length; i++) {
      final node = currentNodes[i];
      final nodeSize = 3.0 + (i % 4) * 1.2;
      final nodeOpacity = (assembleValue * 1.5).clamp(0.0, 1.0);

      // Свечение
      final glowPaint = Paint()
        ..color = Colors.purpleAccent.withValues(alpha: 0.5 * nodeOpacity * pulseValue)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);

      canvas.drawCircle(node, nodeSize * 2 * pulseValue, glowPaint);

      // Ядро
      final nodePaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: nodeOpacity),
            Colors.cyanAccent.withValues(alpha: nodeOpacity * 0.8),
            Colors.purpleAccent.withValues(alpha: nodeOpacity * 0.6),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(Rect.fromCircle(center: node, radius: nodeSize));

      canvas.drawCircle(node, nodeSize * pulseValue, nodePaint);
    }

    // Центральное свечение
    if (assembleValue > 0.5) {
      final glowOpacity = ((assembleValue - 0.5) * 2).clamp(0.0, 1.0);
      final centerGlow = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.cyanAccent.withValues(alpha: 0.2 * glowOpacity * pulseValue),
            Colors.purpleAccent.withValues(alpha: 0.1 * glowOpacity * pulseValue),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(
          center: Offset(size.width / 2, size.height / 2),
          radius: size.width * 0.4,
        ));

      canvas.drawCircle(
        Offset(size.width / 2, size.height / 2),
        size.width * 0.35,
        centerGlow,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NeuralBrainPainter oldDelegate) {
    return oldDelegate.assembleValue != assembleValue ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.signalValue != signalValue;
  }
}

extension _OffsetScale on Offset {
  Offset multiply(double s) => Offset(dx * s, dy * s);
}
