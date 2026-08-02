/// Microvise Design System v2 — kanonik durum/rozet sistemi.
///
/// Denetim raporu (docs/design-system/ui-ux-audit.md §3) en az 4 paralel
/// durum-rozeti implementasyonu tespit etti (AppBadge, İş Emirleri'nin
/// `_compactStatusPill`/`_StatusPill`, kanban'ın inline switch'i) ve aynı
/// durumun ekrana göre 3 farklı etiketle gösterildiğini gösterdi.
///
/// Bu dosya katkı amaçlıdır (additive) — bugün hiçbir ekran buna bağlı
/// değil. Ekran geçişleri (Dashboard'dan başlayarak) sırasında domain'e
/// özel durum kodları (`open`/`in_progress`/... gibi) bu 5 tondan birine
/// eşlenir ve eski `_statusColor`/`_compactStatusPill` gibi yardımcılar
/// silinir. Etiket sözlüğü kasıtlı olarak burada tutulmuyor — durum kodu
/// ↔ Türkçe etiket eşlemesi domain'e (iş emri/servis/fatura) özeldir ve
/// ilgili ekran geçişi yapılırken tek bir yerde (feature-level) tanımlanıp
/// bu tona bağlanır; bu dosya yalnızca *görsel* sözleşmeyi standardize eder.
///
/// Bkz. docs/design-system/microvise-design-system-v2.md §3.1
library;

import 'package:flutter/material.dart';

import '../app/theme/app_theme.dart';

/// Uygulama genelinde anlam taşıyan 5 durum tonu. Yeni bir renk türetmek
/// yasaktır — bir durum bu 5 tondan birine eşlenir.
enum DsStatusTone { info, success, warning, danger, neutral }

Color dsStatusToneColor(DsStatusTone tone) {
  return switch (tone) {
    DsStatusTone.info => AppTheme.blue,
    DsStatusTone.success => AppTheme.success,
    DsStatusTone.warning => AppTheme.warning,
    DsStatusTone.danger => AppTheme.error,
    DsStatusTone.neutral => AppTheme.textMuted,
  };
}

Color dsStatusToneForeground(DsStatusTone tone) =>
    AppTheme.softFg(dsStatusToneColor(tone));

/// Kanonik durum rozeti. `AppBadge` ile aynı görsel dili (soft tint/border,
/// pill radius, aynı tipografi ölçeği) kullanır; farkı `AppBadgeTone`
/// yerine domain-agnostik `DsStatusTone` alması ve opsiyonel önde nokta
/// göstergesi (`showDot`) sunmasıdır.
class DsStatusBadge extends StatelessWidget {
  const DsStatusBadge({
    super.key,
    required this.label,
    required this.tone,
    this.dense = false,
    this.showDot = false,
  });

  final String label;
  final DsStatusTone tone;
  final bool dense;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final color = dsStatusToneColor(tone);
    final fg = dsStatusToneForeground(tone);

    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.softTint(color, alpha: AppTheme.isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.softBorder(
            color,
            alpha: AppTheme.isDark ? 0.32 : 0.24,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
          ],
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: fg,
              fontSize: dense ? 10.5 : 11,
              height: 1.15,
              letterSpacing: 0.05,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Aktif/Pasif" rozeti — bir `bool isActive` alanı taşıyan neredeyse her
/// tanım listesinde (marka, model, arıza tipi, şube, aksesuar tipi, kur,
/// müşteri...) aynı `label: isActive ? 'Aktif' : 'Pasif', tone: isActive ?
/// success : neutral` deseni ayrı ayrı yazılmıştı. Tek kaynak burasıdır.
class DsActiveBadge extends StatelessWidget {
  const DsActiveBadge({
    super.key,
    required this.isActive,
    this.dense = false,
    this.activeLabel = 'Aktif',
    this.inactiveLabel = 'Pasif',
  });

  final bool isActive;
  final bool dense;
  final String activeLabel;
  final String inactiveLabel;

  @override
  Widget build(BuildContext context) {
    return DsStatusBadge(
      label: isActive ? activeLabel : inactiveLabel,
      tone: isActive ? DsStatusTone.success : DsStatusTone.neutral,
      dense: dense,
    );
  }
}

/// Yoğun tablo/liste satırlarında rozet yerine kullanılacak minimal durum
/// göstergesi — `AppDenseList` satırlarında yer kazanmak için.
class DsStatusDot extends StatelessWidget {
  const DsStatusDot({super.key, required this.tone, this.tooltip});

  final DsStatusTone tone;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: dsStatusToneColor(tone),
        shape: BoxShape.circle,
      ),
    );
    if (tooltip == null) return dot;
    return Tooltip(message: tooltip!, child: dot);
  }
}
