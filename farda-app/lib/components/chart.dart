part of '_components.dart';

class AnimatedChart extends StatefulWidget {
  final bool isRtl;
  final Color primaryColor;

  /// The real data series to plot (e.g. adherence over time). Each value is a
  /// fraction in `[0, 1]` where 0 sits at the bottom of the chart and 1 at the
  /// top. When this is null or has fewer than two points there is nothing
  /// honest to draw, so the widget renders the [emptyLabel] placeholder instead
  /// of inventing a curve.
  final List<double>? data;

  /// Text shown when there is no usable [data] to plot.
  final String emptyLabel;

  const AnimatedChart({
    super.key,
    required this.isRtl,
    required this.primaryColor,
    this.data,
    this.emptyLabel = 'No data yet',
  });

  bool get hasData => data != null && data!.length >= 2;

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
    if (!widget.hasData) {
      // No real series yet: show an explicit placeholder, never a fake curve.
      return Center(
        child: Text(
          widget.emptyLabel,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: widget.primaryColor.withValues(alpha: 0.6),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, _) {
        return CustomPaint(
          painter: ChartPainter(
            isRtl: widget.isRtl,
            primaryColor: widget.primaryColor,
            markerScale: _scale.value,
            data: widget.data!,
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

  /// The real series to plot, as fractions in `[0, 1]` (0 = bottom, 1 = top).
  /// Must contain at least two points; callers gate on [AnimatedChart.hasData].
  final List<double> data;

  ChartPainter({
    required this.isRtl,
    required this.primaryColor,
    required this.markerScale,
    required this.data,
  });

  /// Maps the data series to canvas points. Values are clamped to `[0, 1]`,
  /// distributed evenly across the width, and flipped vertically so that a
  /// higher value sits higher on the chart.
  List<Offset> _pointsFor(Size size) {
    final n = data.length;
    final points = <Offset>[];
    for (var i = 0; i < n; i++) {
      final t = n == 1 ? 0.0 : i / (n - 1);
      final v = data[i].clamp(0.0, 1.0).toDouble();
      points.add(Offset(size.width * t, size.height * (1 - v)));
    }
    if (isRtl) {
      return points.map((p) => Offset(size.width - p.dx, p.dy)).toList();
    }
    return points;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return; // Nothing honest to draw.

    final paintLine = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final actualPoints = _pointsFor(size);

    final path = Path()..moveTo(actualPoints[0].dx, actualPoints[0].dy);
    for (int i = 1; i < actualPoints.length; i++) {
      path.lineTo(actualPoints[i].dx, actualPoints[i].dy);
    }

    // Gradient fill (under the path)
    final fillPath = Path.from(path)
      ..lineTo(isRtl ? 0 : size.width, size.height)
      ..lineTo(isRtl ? size.width : 0, size.height)
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

    // Animated marker rings on the interior data points.
    final markerPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (var i = 1; i < actualPoints.length - 1; i++) {
      final p = actualPoints[i];
      canvas.drawCircle(p, 10 * markerScale, markerPaint); // outer ring
      canvas.drawCircle(p, 5 * markerScale, centerPaint); // white inner
      canvas.drawCircle(
        p,
        5 * markerScale,
        paintLine..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ChartPainter oldDelegate) =>
      oldDelegate.markerScale != markerScale ||
      oldDelegate.isRtl != isRtl ||
      oldDelegate.primaryColor != primaryColor ||
      !_sameData(oldDelegate.data, data);

  static bool _sameData(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

