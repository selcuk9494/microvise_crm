import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:google_fonts/google_fonts.dart';

class _AppPalette {
  const _AppPalette({
    required this.primary,
    required this.primaryDark,
    required this.primaryDeep,
    required this.primarySoft,
    required this.accent,
    required this.background,
    required this.backgroundAlt,
    required this.sidebar,
    required this.sidebarText,
    required this.sidebarTextMuted,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceSoft,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textSoft,
    required this.textMuted,
    required this.success,
    required this.warning,
    required this.error,
    required this.hint,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiaryContainer,
    required this.canvasTop,
    required this.canvasMid,
    required this.canvasBottom,
    required this.loginA,
    required this.loginB,
    required this.loginC,
  });

  final Color primary;
  final Color primaryDark;
  final Color primaryDeep;
  final Color primarySoft;
  final Color accent;
  final Color background;
  final Color backgroundAlt;
  final Color sidebar;
  final Color sidebarText;
  final Color sidebarTextMuted;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceSoft;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textSoft;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color error;
  final Color hint;
  final Color secondaryContainer;
  final Color onSecondaryContainer;
  final Color tertiaryContainer;
  final Color canvasTop;
  final Color canvasMid;
  final Color canvasBottom;
  final Color loginA;
  final Color loginB;
  final Color loginC;
}

class AppTheme {
  static Brightness _brightness = Brightness.light;

  /// Sync static palette getters with the resolved Material brightness.
  static void applyBrightness(Brightness value) {
    _brightness = value;
  }

  static Brightness get brightness => _brightness;
  static bool get isDark => _brightness == Brightness.dark;

  /// Light v3 — refined neutral canvas (Linear/Untitled-UI inspired), same
  /// brand blue, softer semantic accents so status pills read calmer.
  static const _AppPalette _light = _AppPalette(
    primary: Color(0xFF2563EB),
    primaryDark: Color(0xFF1D4ED8),
    primaryDeep: Color(0xFF1E40AF),
    primarySoft: Color(0xFFDBEAFE),
    accent: Color(0xFF3B82F6),
    background: Color(0xFFF4F7FB),
    backgroundAlt: Color(0xFFF8FAFC),
    sidebar: Color(0xFFFFFFFF),
    sidebarText: Color(0xFF202A3C),
    sidebarTextMuted: Color(0xFF69768A),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF8FAFC),
    surfaceSoft: Color(0xFFF1F5F9),
    border: Color(0xFFDFE5ED),
    borderStrong: Color(0xFF9AA6B6),
    text: Color(0xFF202A3C),
    textSoft: Color(0xFF425066),
    textMuted: Color(0xFF69768A),
    success: Color(0xFF16845A),
    warning: Color(0xFFF79009),
    error: Color(0xFFC8424B),
    hint: Color(0xFF8B97A8),
    secondaryContainer: Color(0xFFDBEAFE),
    onSecondaryContainer: Color(0xFF1E40AF),
    tertiaryContainer: Color(0xFFF2F4F7),
    canvasTop: Color(0xFFFAFBFC),
    canvasMid: Color(0xFFF8F9FB),
    canvasBottom: Color(0xFFF1F3F6),
    loginA: Color(0xFF12141A),
    loginB: Color(0xFF161A24),
    loginC: Color(0xFF1D2436),
  );

  /// Dark v3 — deeper, richer charcoal shell (Linear-style near-black), same
  /// blue chrome, softer semantic accents so long lists don't glare.
  static const _AppPalette _dark = _AppPalette(
    primary: Color(0xFF2563EB),
    primaryDark: Color(0xFF3B82F6),
    primaryDeep: Color(0xFF60A5FA),
    primarySoft: Color(0xFF242D4D),
    accent: Color(0xFF3B82F6),
    background: Color(0xFF11151B),
    backgroundAlt: Color(0xFF141920),
    sidebar: Color(0xFF151A22),
    sidebarText: Color(0xFFE2E7EE),
    sidebarTextMuted: Color(0xFF98A3B3),
    surface: Color(0xFF181D25),
    surfaceMuted: Color(0xFF1C222C),
    surfaceSoft: Color(0xFF202731),
    border: Color(0xFF2B333E),
    borderStrong: Color(0xFF4A5564),
    text: Color(0xFFE2E7EE),
    textSoft: Color(0xFFC5CDD8),
    textMuted: Color(0xFF98A3B3),
    success: Color(0xFF63C99C),
    warning: Color(0xFFE8B45C),
    error: Color(0xFFFF8990),
    hint: Color(0xFF788596),
    secondaryContainer: Color(0xFF1D3252),
    onSecondaryContainer: Color(0xFF93C5FD),
    tertiaryContainer: Color(0xFF212227),
    canvasTop: Color(0xFF15161A),
    canvasMid: Color(0xFF101114),
    canvasBottom: Color(0xFF0B0C0F),
    loginA: Color(0xFF0B0C0F),
    loginB: Color(0xFF101114),
    loginC: Color(0xFF1A1B1F),
  );

  static _AppPalette get _p => isDark ? _dark : _light;

  // Hybrid A/D: Inter UI, ink rail (light) / warm charcoal (dark), blue accents.
  static Color get primary => _p.primary;
  static Color get primaryDark => _p.primaryDark;
  static Color get primaryDeep => _p.primaryDeep;
  static Color get primarySoft => _p.primarySoft;
  static Color get accent => _p.accent;
  static Color get background => _p.background;
  static Color get backgroundAlt => _p.backgroundAlt;
  static Color get sidebar => _p.sidebar;
  static Color get sidebarText => _p.sidebarText;
  static Color get sidebarTextMuted => _p.sidebarTextMuted;
  static Color get surface => _p.surface;
  static Color get surfaceMuted => _p.surfaceMuted;
  static Color get surfaceSoft => _p.surfaceSoft;
  static Color get border => _p.border;
  static Color get borderStrong => _p.borderStrong;
  static Color get text => _p.text;
  static Color get textSoft => _p.textSoft;
  static Color get textMuted => _p.textMuted;

  static Color get success => _p.success;
  static Color get warning => _p.warning;
  static Color get error => _p.error;

  /// Semantic accents (KPI wells / charts / status). Green only for success.
  static const Color green = Color(0xFF22C55E);
  static const Color orange = Color(0xFFF59E0B);

  /// Blue primary companions (charts / KPI chrome).
  static const Color blue = Color(0xFF2563EB);
  static const Color blueBright = Color(0xFF60A5FA);
  static const Color red = Color(0xFFEF4444);
  static const Color purple = Color(0xFFA855F7);
  static const Color yellow = Color(0xFFEAB308);

  /// Soft ink lift used for Option A active nav pill.
  static const Color sidebarActiveFill = Color(0xFFEEF1FF);

  /// Aliases used by dashboard / charts.
  static const Color metricOrange = orange;
  static const Color metricBlue = blue;
  static const Color metricPurple = purple;
  static const Color metricRed = red;
  static const Color metricGreen = green;
  static const Color metricYellow = yellow;
  static const Color metricAmber = orange;

  /// @Deprecated — use [metricBlue]; kept as alias so charts stay on blue chrome.
  static const Color metricTeal = blue;

  /// @Deprecated — use [blue] / [primary]; leftover name for call sites.
  static const Color teal = blueBright;

  /// Duotone icon well: a semantic line color on a restrained tinted surface.
  static BoxDecoration categoryIconWell(Color accent, {double radius = 10}) =>
      BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: accent.withValues(alpha: isDark ? 0.24 : 0.15),
        ),
      );

  static Color categoryIconFg(Color accent) => isDark
      ? Color.alphaBlend(accent.withValues(alpha: 0.70), text)
      : Color.alphaBlend(accent.withValues(alpha: 0.88), textSoft);

  /// Sidebar selection stays quiet: a slim accent rail plus a faint surface.
  static BoxDecoration sidebarNavDecoration({required bool active}) {
    if (!active) {
      return const BoxDecoration(color: Colors.transparent);
    }
    return BoxDecoration(
      color: primary.withValues(alpha: isDark ? 0.08 : 0.055),
      borderRadius: BorderRadius.circular(6),
      border: Border(left: BorderSide(color: primary, width: 3)),
    );
  }

  static Color sidebarNavFg({required bool active}) {
    if (!active) return sidebarTextMuted;
    return isDark ? const Color(0xFF8BA5FF) : const Color(0xFF3157D5);
  }

  static const double radiusXs = 7;
  static const double radiusSm = 9;
  static const double radiusMd = 10;
  static const double radiusLg = 12;
  static const double radiusXl = 14;

  static const EdgeInsets pagePaddingDesktop = EdgeInsets.symmetric(
    horizontal: 28,
    vertical: 20,
  );
  static const EdgeInsets pagePaddingTablet = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 16,
  );
  static const EdgeInsets pagePaddingMobile = EdgeInsets.symmetric(
    horizontal: 16,
    vertical: 14,
  );

  /// CRM surfaces are flat; hierarchy comes from spacing and hairline borders.
  static List<BoxShadow> get cardShadow => const <BoxShadow>[];

  static List<BoxShadow> get hoverShadow => const <BoxShadow>[];

  static BoxDecoration get pageCanvas => BoxDecoration(color: background);

  /// Navy auth backdrop — continuous with brand accent family.
  static BoxDecoration get loginCanvas => BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [_p.loginA, _p.loginB, _p.loginC],
      stops: const [0.0, 0.52, 1.0],
    ),
  );

  static BoxDecoration get panelSurface => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(radiusMd),
    border: Border.all(
      color: border.withValues(alpha: isDark ? 1.0 : 0.72),
      width: isDark ? 1 : 1,
    ),
    boxShadow: cardShadow,
  );

  /// Soft tinted chip/badge fill — readable tint, not neon solid pills.
  static Color softTint(Color color, {double alpha = 0.14}) =>
      color.withValues(alpha: isDark ? (alpha < 0.18 ? 0.22 : alpha) : alpha);

  static Color softBorder(Color color, {double alpha = 0.22}) =>
      color.withValues(alpha: isDark ? (alpha < 0.30 ? 0.38 : alpha) : alpha);

  /// Status/chip foreground — readable but muted, not neon. Long lists (e.g.
  /// invoice tables with a status/e-fatura/ERP badge on every row) looked
  /// visually noisy with a more saturated blend; this keeps hue recognizable
  /// while calming it down.
  static Color softFg(Color color) => isDark
      ? Color.alphaBlend(color.withValues(alpha: 0.52), text)
      : Color.alphaBlend(color.withValues(alpha: 0.76), textSoft);

  /// Compact filter/select chrome — muted surface, blue-family accents only.
  static Color get filterControlBg => isDark ? surfaceSoft : surface;
  static Color get filterControlFg => textSoft;
  static Color get tableHeaderBg => isDark ? surfaceSoft : surfaceMuted;

  static ThemeData light() => _themeFor(_light, Brightness.light);

  static ThemeData dark() => _themeFor(_dark, Brightness.dark);

  static ThemeData _themeFor(_AppPalette p, Brightness brightness) {
    final fontFamily = GoogleFonts.inter().fontFamily;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: fontFamily,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: p.primary,
        onPrimary: Colors.white,
        secondary: p.accent,
        onSecondary: AppTheme.text,
        error: p.error,
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.text,
        outline: p.border,
        primaryContainer: p.primarySoft,
        onPrimaryContainer: brightness == Brightness.dark
            ? p.primaryDark
            : p.primaryDeep,
        secondaryContainer: p.secondaryContainer,
        onSecondaryContainer: p.onSecondaryContainer,
        tertiaryContainer: p.tertiaryContainer,
        onTertiaryContainer: p.textSoft,
        surfaceContainerHighest: p.surfaceMuted,
        surfaceContainerHigh: p.surface,
        surfaceContainer: p.surfaceMuted,
      ),
      scaffoldBackgroundColor: p.background,
      visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
    );

    // Restrained hierarchy: weight is reserved for headings and selection.
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
      headlineSmall: GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: 22,
        color: p.text,
        letterSpacing: -0.3,
      ),
      titleLarge: GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: 20,
        color: p.text,
        letterSpacing: -0.25,
      ),
      titleMedium: GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: 16,
        color: p.text,
        letterSpacing: -0.1,
      ),
      titleSmall: GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: 13,
        color: p.text,
      ),
      bodyLarge: GoogleFonts.inter(
        fontWeight: FontWeight.w400,
        fontSize: 15,
        color: p.text,
        height: 1.4,
      ),
      bodyMedium: GoogleFonts.inter(
        fontWeight: FontWeight.w400,
        fontSize: 13,
        color: p.textSoft,
        height: 1.4,
      ),
      bodySmall: GoogleFonts.inter(
        fontWeight: FontWeight.w400,
        fontSize: 11.5,
        color: p.textMuted,
        height: 1.35,
      ),
      labelLarge: GoogleFonts.inter(
        fontWeight: FontWeight.w600,
        fontSize: 13,
        color: p.text,
      ),
      labelMedium: GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: 12,
        color: p.text,
      ),
      labelSmall: GoogleFonts.inter(
        fontWeight: FontWeight.w500,
        fontSize: 11,
        color: p.textMuted,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: IconThemeData(
        color: p.textSoft,
        size: 18,
        fill: 0,
        weight: 400,
        opticalSize: 20,
      ),
      primaryIconTheme: IconThemeData(
        color: p.primary,
        size: 18,
        fill: 0,
        weight: 400,
        opticalSize: 20,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
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
      dividerTheme: DividerThemeData(
        color: p.border.withValues(alpha: 0.85),
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(
            color: p.border.withValues(
              alpha: brightness == Brightness.dark ? 1.0 : 0.65,
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXs),
          borderSide: BorderSide(color: p.border.withValues(alpha: 0.8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXs),
          borderSide: BorderSide(color: p.border.withValues(alpha: 0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXs),
          borderSide: BorderSide(color: p.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXs),
          borderSide: BorderSide(color: p.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXs),
          borderSide: BorderSide(color: p.error, width: 1.5),
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(color: p.hint),
        labelStyle: textTheme.bodyMedium?.copyWith(color: p.textSoft),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          iconColor: Colors.white,
          iconSize: 16,
          iconAlignment: IconAlignment.start,
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXs),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: base.colorScheme.onSurface,
          iconColor: p.text,
          iconSize: 16,
          iconAlignment: IconAlignment.start,
          side: BorderSide(color: p.border.withValues(alpha: 0.9)),
          minimumSize: const Size(0, 40),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXs),
          ),
          backgroundColor: p.surface.withValues(alpha: 0.7),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.primary,
          iconColor: p.primary,
          iconSize: 16,
          iconAlignment: IconAlignment.start,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: p.textSoft,
          iconSize: 18,
          minimumSize: const Size(38, 38),
          padding: const EdgeInsets.all(8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusXs),
          ),
          hoverColor: p.surfaceSoft,
          highlightColor: p.primary.withValues(alpha: 0.08),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.transparent,
        selectedColor: p.primarySoft,
        side: BorderSide(color: p.border),
        labelStyle: textTheme.labelMedium!.copyWith(color: p.textSoft),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXs),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: brightness == Brightness.dark
            ? p.surfaceSoft
            : p.primaryDeep,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.primaryDark,
        unselectedLabelColor: p.textMuted,
        dividerHeight: 0,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: p.primarySoft.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(radiusXs),
          border: Border.all(color: p.primary.withValues(alpha: 0.14)),
        ),
        dividerColor: Colors.transparent,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        splashFactory: NoSplash.splashFactory,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        labelPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: p.border.withValues(alpha: 0.55)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primary,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radiusMd)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSoft,
        textColor: p.text,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXs),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(p.surfaceMuted),
        dataRowColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.primary.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        headingTextStyle: textTheme.labelMedium?.copyWith(color: p.textMuted),
        dataTextStyle: textTheme.bodyMedium?.copyWith(color: p.text),
        dividerThickness: 1,
        decoration: BoxDecoration(
          border: Border.all(color: p.border),
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.primary,
        linearTrackColor: p.surfaceSoft,
        circularTrackColor: p.surfaceSoft,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.primary,
        selectionColor: p.primarySoft,
        selectionHandleColor: p.primary,
      ),
      checkboxTheme: CheckboxThemeData(
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: p.borderStrong, width: 1.4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.primary
              : Colors.transparent,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(p.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSm),
              side: BorderSide(color: p.border),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          side: BorderSide(color: p.border),
        ),
        textStyle: textTheme.bodyMedium?.copyWith(color: p.text),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: brightness == Brightness.dark
              ? const Color(0xFFF2F4F7)
              : const Color(0xFF182230),
          borderRadius: BorderRadius.circular(6),
        ),
        textStyle: textTheme.bodySmall?.copyWith(
          color: brightness == Brightness.dark
              ? const Color(0xFF182230)
              : const Color(0xFFF2F4F7),
        ),
        waitDuration: const Duration(milliseconds: 350),
      ),
    );
  }
}
