import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum FardaScene { today, calendar, refills, you }

/// Exact, locally exported Figma scene artwork behind responsive Flutter content.
class FardaSceneCard extends StatelessWidget {
  const FardaSceneCard({
    super.key,
    required this.scene,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  final FardaScene scene;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow:
            scene == FardaScene.today
                ? const [
                  BoxShadow(
                    color: Color(0x26142C55),
                    offset: Offset(0, 9),
                    blurRadius: 20,
                  ),
                ]
                : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: SvgPicture.asset(
                  'assets/figma/scene-${scene.name}.svg',
                  fit: BoxFit.fill,
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// Figma's icon vectors, with semantic labels provided by their controls.
class FardaVectorIcon extends StatelessWidget {
  const FardaVectorIcon(this.name, {super.key, this.size = 22, this.color});
  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/figma/$name.svg',
      width: size,
      height: size,
      colorFilter:
          color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
    ),
  );
}
