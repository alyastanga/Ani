import 'package:flutter/widgets.dart';

/// Colour tokens carried over from the Figma Make prototype (`src/index.css`).
abstract final class AniColors {
  static const Color cream = Color(0xFFF5EFE3);
  static const Color paper = Color(0xFFFFFDF8);
  static const Color olive = Color(0xFF4F5B2A);
  static const Color oliveDark = Color(0xFF354019);
  static const Color gold = Color(0xFFB8892D);
  static const Color sand = Color(0xFFD8C9A8);
  static const Color ink = Color(0xFF29301B);
  static const Color muted = Color(0xFF797B69);
  static const Color line = Color(0xFFDFD8C9);

  /// Dryness alert levels (Alert Machine): Normal / Bantay / Delikado.
  static const Color statusNormal = Color(0xFF5F7A32);
  static const Color statusBantay = gold;
  static const Color statusDelikado = Color(0xFFA4442F);

  /// Pale fills for banners/pills behind each status colour.
  static const Color statusNormalBg = Color(0xFFE9EEDB);
  static const Color statusBantayBg = Color(0xFFF5E9CF);
  static const Color statusDelikadoBg = Color(0xFFF3DED7);
}

/// Spacing scale (logical pixels), 4-pt based.
abstract final class AniSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;

  /// Default horizontal screen padding.
  static const double screen = 16;
}

/// Corner radii.
abstract final class AniRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double pill = 999;

  static const BorderRadius card = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius tile = BorderRadius.all(Radius.circular(md));
  static const BorderRadius button = BorderRadius.all(Radius.circular(md));
  static const BorderRadius chip = BorderRadius.all(Radius.circular(pill));
}

/// Font family bundled as an asset (declared in pubspec.yaml).
const String aniFontFamily = 'AsapCondensed';
