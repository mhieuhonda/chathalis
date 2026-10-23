import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// The Halis "H" mark — two rounded bars joined by a crossbar.
///
/// Drawn rather than rasterized so it stays crisp at every size, from the
/// 14px avatar chip to the 72px empty-state glyph.
class HalisMark extends StatelessWidget {
  const HalisMark({super.key, this.size = 24, this.color = HalisPalette.paper});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _HalisMarkPainter(color),
    );
  }
}

class _HalisMarkPainter extends CustomPainter {
  _HalisMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Geometry mirrored from the launcher icon: total box 500×440,
    // bar width 118, corner radius 59.
    final w = size.width;
    final h = size.height;
    final sx = w / 500;
    final sy = h / 440;

    RRect bar(double left, double top, double right, double bottom) {
      final r = 59 * ((sx + sy) / 2);
      return RRect.fromRectAndCorners(
        Rect.fromLTRB(left * sx, top * sy, right * sx, bottom * sy),
        topLeft: Radius.circular(r),
        topRight: Radius.circular(r),
        bottomLeft: Radius.circular(r),
        bottomRight: Radius.circular(r),
      );
    }

    canvas.drawRRect(bar(0, 0, 118, 440), paint);
    canvas.drawRRect(bar(382, 0, 500, 440), paint);
    canvas.drawRRect(bar(0, 164, 500, 276), paint);
  }

  @override
  bool shouldRepaint(covariant _HalisMarkPainter old) => old.color != color;
}

/// Round ink chip with the white mark — the assistant avatar.
class HalisAvatar extends StatelessWidget {
  const HalisAvatar({super.key, this.size = 30});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: HalisPalette.ink,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: HalisMark(size: size * 0.46, color: HalisPalette.paper),
      ),
    );
  }
}
