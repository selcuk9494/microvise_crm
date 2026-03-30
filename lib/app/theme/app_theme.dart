import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primary = Color(0xFF1D4ED8);
  static const Color primaryDark = Color(0xFF1E3A8A);
  static const Color primaryDeep = Color(0xFF163FA6);
  static const Color primarySoft = Color(0xFFE8F0FF);
  static const Color accent = Color(0xFF0F766E);
  static const Color background = Color(0xFFF3F7FC);
  static const Color backgroundAlt = Color(0xFFE9F0FA);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF8FAFD);
  static const Color surfaceSoft = Color(0xFFF6F9FD);
  static const Color border = Color(0xFFD9E2EE);
  static const Color borderStrong = Color(0xFFC6D3E3);
  static const Color text = Color(0xFF0F172A);
  static const Color textSoft = Color(0xFF475569);
  static const Color textMuted = Color(0xFF64748B);

  static const Color success = Color(0xFF22C55E);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFE11D48);

  static const double radiusXs = 8;
  static const double radiusSm = 12;
  static const double radiusMd = 16;
  static const double radiusLg = 20;

  static const EdgeInsets pagePaddingDesktop = EdgeInsets.symmetric(
    horizontal: 24,
    vertical: 18,
  );
  static const EdgeInsets pagePaddingTablet = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 14,
  );
  static const EdgeInsets pagePaddingMobile = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 10,
  );

  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.035),
      blurRadius: 22,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get hoverShadow => [
    BoxShadow(
      color: primaryDark.withValues(alpha: 0.08),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: primary,
        secondary: accent,
        surface: surface,
        error: error,
        onPrimary: Colors.white,
        onSurface: text,
        outline: border,
      ),
      scaffoldBackgroundColor: background,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    );

    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme).copyWith(
      headlineSmall: GoogleFonts.manrope(
        fontWeight: FontWeight.w800,
        fontSize: 22,
        color: text,
        letterSpacing: -0.5,
      ),
      titleLarge: GoogleFonts.manrope(
        fontWeight: FontWeight.w800,
        fontSize: 20,
        color: text,
        letterSpacing: -0.4,
      ),
      titleMedium: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        fontSize: 16,
        color: text,
      ),
      titleSmall: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: text,
      ),
      bodyLarge: GoogleFonts.manrope(
        fontWeight: FontWeight.w500,
        fontSize: 15,
        color: text,
        height: 1.32,
      ),
      bodyMedium: GoogleFonts.manrope(
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: textSoft,
        height: 1.3,
      ),
      bodySmall: GoogleFonts.manrope(
        fontWeight: FontWeight.w500,
        fontSize: 11,
        color: textMuted,
        height: 1.3,
      ),
      labelLarge: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: text,
      ),
      labelMedium: GoogleFonts.manrope(
        fontWeight: FontWeight.w700,
        fontSize: 12,
        color: text,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: base.colorScheme.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      dividerTheme: const DividerThemeData(color: border, space: 1),
      cardTheme: const CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
          side: BorderSide(color: border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: const BorderSide(color: error, width: 1.6),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: const Color(0xFF8CA0B8),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(color: textSoft),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: Colors.white,
          elevation: 0,
          iconColor: Colors.white,
          iconSize: 16,
          iconAlignment: IconAlignment.start,
          minimumSize: const Size(0, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: base.colorScheme.onSurface,
          iconColor: text,
          iconSize: 16,
          iconAlignment: IconAlignment.start,
          side: const BorderSide(color: border),
          minimumSize: const Size(0, 42),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
          backgroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          iconColor: primary,
          iconSize: 16,
          iconAlignment: IconAlignment.start,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: text,
          iconSize: 20,
          minimumSize: const Size(38, 38),
          padding: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSm),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF0B1220),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: primaryDark,
        unselectedLabelColor: textMuted,
        dividerHeight: 1,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: primarySoft.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(radiusSm),
          border: Border.all(color: primary.withValues(alpha: 0.18)),
        ),
        dividerColor: border,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        labelPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: const BorderSide(color: border),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryDark,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: textSoft,
        textColor: text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
        ),
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: primaryDark,
        selectionColor: primarySoft,
        selectionHandleColor: primaryDark,
      ),
    );
  }
}
