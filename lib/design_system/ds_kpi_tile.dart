/// Microvise Design System v2 — kanonik KPI / istatistik kartı.
///
/// Denetim raporu üç ayrı "küçük istatistik kutusu" implementasyonu tespit
/// etti: Dashboard'un sparkline'lı `_MetricTile`'ı, Servis'in `_MetricCard`'ı
/// ve kit içindeki kullanılmayan `CompactStatCard`. `DsKpiTile` bu üçünün
/// yerini alacak tek bileşendir: ikon well + etiket + değer + opsiyonel
/// trend (sparkline veya yüzde delta oku) + opsiyonel tıklanabilirlik.
///
/// Katkı amaçlıdır (additive) — bugün hiçbir ekran buna bağlı değil.
///
/// Bkz. docs/design-system/microvise-design-system-v2.md §3.4
library;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../app/theme/app_theme.dart';
import 'ds_tokens.dart';

class DsKpiTile extends StatelessWidget {
  const DsKpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accentColor,
    this.subtitle,
    this.subtitleColor,
    this.trendPercent,
    this.sparkline,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accentColor;

  /// Değerin yanında gösterilecek ikincil metin (ör. tutar). Verilmişse
  /// [trendPercent] gizlenir — ikisi aynı anda gösterilmez.
  final String? subtitle;
  final Color? subtitleColor;

  /// Örn. 12.4 → "+%12,4" yeşil ok; -3.1 → "-%3,1" kırmızı ok.
  /// `subtitle` veya `sparkline` verilmişse bu göz ardı edilir.
  final double? trendPercent;

  /// Son N günün ham değerleri — verilirse mini sparkline çizilir.
  /// Yalnızca gerçek bir zaman serisi mevcutsa doldurulmalı; gerçek veri
  /// yoksa `null` bırakılmalı (dekoratif/sahte çizgi üretilmez).
  final List<double>? sparkline;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpace.lg,
        vertical: DsSpace.md,
      ),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.65)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: AppTheme.categoryIconWell(accentColor),
            child: Icon(
              icon,
              size: 18,
              color: AppTheme.categoryIconFg(accentColor),
            ),
          ),
          const Gap(DsSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Gap(2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (subtitle != null) ...[
                      const Gap(6),
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: subtitleColor ?? AppTheme.textMuted,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                    ] else if (trendPercent != null && sparkline == null) ...[
                      const Gap(6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: _TrendDelta(percent: trendPercent!),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (sparkline != null && sparkline!.length >= 2) ...[
            const Gap(DsSpace.sm),
            SizedBox(
              width: 56,
              height: 28,
              child: CustomPaint(
                painter: _SparklinePainter(
                  values: sparkline!,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class _TrendDelta extends StatelessWidget {
  const _TrendDelta({required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final isUp = percent >= 0;
    // Ham AppTheme.success/error metin olarak düşük kontrastlı (hesaplandı:
    // light'ta yeşil ~3.3:1). AppTheme.softFg — uygulamanın rozet/durum
    // metinlerinde zaten kullandığı okunabilirlik dönüşümü — burada da
    // uygulanıyor (yeşil ~3.8:1'e, kırmızı ~5.5:1'e çıkıyor).
    final color = AppTheme.softFg(isUp ? AppTheme.success : AppTheme.error);
    final formatted = percent.abs().toStringAsFixed(1).replaceAll('.', ',');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 12,
          color: color,
        ),
        Text(
          '%$formatted',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final stepX = size.width / (values.length - 1);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * stepX;
      final normalized = (values[i] - minV) / range;
      final y = size.height - (normalized * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
