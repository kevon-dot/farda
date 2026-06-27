part of '_components.dart';

class AnimatedChart extends StatefulWidget {
  final bool isRtl;
  final Color primaryColor;

  const AnimatedChart({
    super.key,
    required this.isRtl,
    required this.primaryColor,
  });

  @override
  State<AnimatedChart> createState() => _AnimatedChartState();
}

class _AnimatedChartState extends State<AnimatedChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..forward();

    _scale = Tween<double>(
      begin: 0.3,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, _) {
        return CustomPaint(
          painter: ChartPainter(
            isRtl: widget.isRtl,
            primaryColor: widget.primaryColor,
            markerScale: _scale.value,
          ),
          child: const SizedBox(height: 100, width: double.infinity),
        );
      },
    );
  }
}

class ChartPainter extends CustomPainter {
  final bool isRtl;
  final Color primaryColor;
  final double markerScale;

  ChartPainter({
    required this.isRtl,
    required this.primaryColor,
    required this.markerScale,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paintLine = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final path = Path();
    final points = [
      Offset(0, size.height),
      Offset(size.width * 0.30, size.height * 0.3),
      Offset(size.width * 0.70, size.height * 0.4),
      Offset(size.width, 0),
    ];

    final actualPoints = isRtl
        ? points.map((p) => Offset(size.width - p.dx, p.dy)).toList()
        : points;

    path.moveTo(actualPoints[0].dx, actualPoints[0].dy);
    for (int i = 1; i < actualPoints.length; i++) {
      path.lineTo(actualPoints[i].dx, actualPoints[i].dy);
    }

    // Gradient fill (under the path)
    final fillPath = Path.from(path)
      ..lineTo(isRtl ? 0 : size.width, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [primaryColor.withValues(alpha: 0.3), Colors.transparent],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paintLine);

    // Animated Marker rings
    final markerPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final markerPositions = [actualPoints[1], actualPoints[2]];
    for (var p in markerPositions) {
      canvas.drawCircle(p, 10 * markerScale, markerPaint); // outer ring
      canvas.drawCircle(p, 5 * markerScale, centerPaint);  // white inner
      canvas.drawCircle(p, 5 * markerScale, paintLine..style = PaintingStyle.stroke);
    }
  }

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.markerScale != markerScale ||
          oldDelegate.isRtl != isRtl ||
          oldDelegate.primaryColor != primaryColor;
}

