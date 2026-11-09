import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/glass_mode.dart';
import '../core/theme/theme_extensions.dart';

// Posisi dan ukuran cahaya diambil dari artboard
// design/export/artboards/Foundations.dc.html (baris latar):
//   radial-gradient(60% 90% at 85% 20%, glowA, transparent 70%),
//   radial-gradient(60% 90% at 10% 90%, glowB, transparent 70%).
// Ini konstanta tata letak, bukan token warna.
const _glowRadiusXFactor = 0.6;
const _glowRadiusYFactor = 0.9;
const _glowFadeStop = 0.7;
const _glowACenter = Offset(0.85, 0.20);
const _glowBCenter = Offset(0.10, 0.90);

/// Latar app: warna dasar `surface` dan dua cahaya radial statis.
///
/// Cahaya digambar satu kali sebagai [RadialGradient] tanpa animasi dan tanpa
/// `BackdropFilter`. Saat fallback solid aktif (high contrast, reduce
/// transparency, atau slow raster), cahaya dimatikan dan hanya warna dasar
/// yang tampil (design-system.md section 7, R06).
class LightBackdrop extends ConsumerWidget {
  const LightBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final solid = GlassMode.isSolid(context, ref);
    final glowTokens = context.backdrop;

    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: LightBackdropPainter(
              base: Theme.of(context).colorScheme.surface,
              glowA: glowTokens.glowA,
              glowB: glowTokens.glowB,
              glows: !solid,
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// Menggambar warna dasar lalu, bila [glows], dua cahaya radial.
class LightBackdropPainter extends CustomPainter {
  const LightBackdropPainter({
    required this.base,
    required this.glowA,
    required this.glowB,
    required this.glows,
  });

  final Color base;
  final Color glowA;
  final Color glowB;
  final bool glows;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    if (!glows) return;
    _paintGlow(canvas, size, glowA, _glowACenter);
    _paintGlow(canvas, size, glowB, _glowBCenter);
  }

  void _paintGlow(Canvas canvas, Size size, Color glow, Offset center) {
    // Lingkaran radius 1 di ruang lokal, diskalakan menjadi elips seukuran
    // 60% x 90% layar. Shader ikut transform kanvas.
    final rect = Rect.fromCircle(center: Offset.zero, radius: 1);
    final shader = RadialGradient(
      colors: [glow, glow.withAlpha(0)],
      stops: const [0, _glowFadeStop],
    ).createShader(rect);

    canvas.save();
    canvas.translate(center.dx * size.width, center.dy * size.height);
    canvas.scale(
      _glowRadiusXFactor * size.width,
      _glowRadiusYFactor * size.height,
    );
    canvas.drawCircle(Offset.zero, 1, Paint()..shader = shader);
    canvas.restore();
  }

  @override
  bool shouldRepaint(LightBackdropPainter oldDelegate) =>
      oldDelegate.base != base ||
      oldDelegate.glowA != glowA ||
      oldDelegate.glowB != glowB ||
      oldDelegate.glows != glows;
}
