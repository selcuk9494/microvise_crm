/// Microvise Design System v2 — layout & motion tokens.
///
/// Bu dosya katkı amaçlıdır (additive): hiçbir mevcut ekran veya
/// `lib/core/ui/*` bileşeni bunu henüz kullanmıyor. Renk token'ları için
/// tek kaynak hâlâ `AppTheme`'dir — burada yalnızca `AppTheme`'de bugün
/// bulunmayan spacing/elevation/motion ölçekleri tanımlanır.
///
/// Bkz. docs/design-system/microvise-design-system-v2.md §1.3
library;

import 'package:flutter/animation.dart';

/// 4pt taban spacing ölçeği. Serbest sayı yalnızca bileşen iç boşluğunda
/// (ör. buton padding'i) istisnadır; sayfa/kart aralıklarında bu ölçek
/// kullanılır.
class DsSpace {
  const DsSpace._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xl2 = 24;
  static const double xl3 = 32;
  static const double xl4 = 40;
  static const double xl5 = 48;
}

/// Yükselti seviyeleri. `AppTheme.cardShadow` / `AppTheme.hoverShadow` ile
/// hizalıdır; dialog/sheet/popover için eksik olan 3. seviyeyi ekler.
class DsElevation {
  const DsElevation._();

  /// Zemin — gölge yok.
  static const double flat = 0;

  /// Kart — `AppTheme.cardShadow` (blur 14, offset 0/3, alpha 0.045).
  static const double card = 1;

  /// Hover / dropdown — `AppTheme.hoverShadow`.
  static const double raised = 2;

  /// Dialog / bottom sheet / popover — light'ta blur 24 offset 0/8 alpha
  /// 0.08; dark'ta gölgesiz, yalnızca 1px border (mevcut dialogTheme ile
  /// aynı yaklaşım).
  static const double overlay = 3;
}

/// Hareket süreleri. `AppShell` bugün 160ms (fast) kullanıyor; burada
/// resmileştirilip eksik kademeler (instant/base/slow) ekleniyor.
class DsMotion {
  const DsMotion._();

  static const Duration instant = Duration(milliseconds: 100);
  static const Duration fast = Duration(milliseconds: 160);
  static const Duration base = Duration(milliseconds: 220);
  static const Duration slow = Duration(milliseconds: 320);

  static const Curve enter = Curves.easeOut;
  static const Curve exit = Curves.easeIn;
}

/// Responsive breakpoint sabitleri — `AppBreakpoints` ile aynı ölçek,
/// ek olarak `SmartFilterBar`/`AppPageLayout` içinde bugün ekran ekran
/// farklı seçilen ara kademeleri (900 vs 980) tek noktada topluyor.
class DsBreakpoints {
  const DsBreakpoints._();

  static const double mobile = 559;
  static const double compact = 899;
  static const double filterBarWide = 980;
  static const double tablet = 1023;
  static const double desktop = 1024;
  static const double wide = 1440;
}
