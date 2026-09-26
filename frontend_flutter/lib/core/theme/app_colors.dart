import 'package:flutter/material.dart';

/// LocalIQ brand palette: deep indigo/plurple with a warm accent.
abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFF6C4CE0);
  static const Color primaryDark = Color(0xFF4F35B8);
  static const Color indigo = Color(0xFF4F46E5);
  static const Color deep = Color(0xFF1B1436);
  static const Color deepAlt = Color(0xFF2A1E5C);

  // Surfaces
  static const Color background = Color(0xFFF6F5FB);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF1EFFA);
  static const Color divider = Color(0xFFE7E4F3);

  // Text
  static const Color textPrimary = Color(0xFF15132B);
  static const Color textSecondary = Color(0xFF6E6B85);
  static const Color textOnBrand = Color(0xFFFFFFFF);

  // Accents
  static const Color lavender = Color(0xFFEFEBFF);
  static const Color star = Color(0xFFFFB020);
  static const Color open = Color(0xFF15A34A);
  static const Color closed = Color(0xFFE5484D);
  static const Color mapRoute = Color(0xFFEF4444);

  /// Deterministic gradient pairs used for image placeholders.
  static const List<List<Color>> placeholderGradients = <List<Color>>[
    <Color>[Color(0xFF6C4CE0), Color(0xFF9F7AEA)],
    <Color>[Color(0xFF4F46E5), Color(0xFF7C8AF5)],
    <Color>[Color(0xFF0EA5A5), Color(0xFF5EEAD4)],
    <Color>[Color(0xFFF97316), Color(0xFFFDBA74)],
    <Color>[Color(0xFFDB2777), Color(0xFFF9A8D4)],
    <Color>[Color(0xFF1D4ED8), Color(0xFF7DD3FC)],
  ];
}
