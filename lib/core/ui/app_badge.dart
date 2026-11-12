import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    required this.tone,
    this.dense = false,
  });

  final String label;
  final AppBadgeTone tone;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AppBadgeTone.success => AppTheme.success,
      AppBadgeTone.warning => AppTheme.warning,
      AppBadgeTone.error => AppTheme.error,
      AppBadgeTone.neutral => AppTheme.textMuted,
      AppBadgeTone.primary => AppTheme.primary,
    };
    // Option C + yüksek kontrast: ortak slate yüzey, anlam sol rayda;
    // yazı textSoft üzerine boyanır ki koyu zeminde okunur kalsın.
    final fg = Color.alphaBlend(
      color.withValues(alpha: AppTheme.isDark ? 0.82 : 0.88),
      AppTheme.isDark ? AppTheme.text : AppTheme.textSoft,
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.isDark
            ? const Color(0xFF243044)
            : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(
          color: AppTheme.border.withValues(
            alpha: AppTheme.isDark ? 0.95 : 0.9,
          ),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: color),
            Padding(
              padding: dense
                  ? const EdgeInsets.fromLTRB(6, 2, 6, 2)
                  : const EdgeInsets.fromLTRB(7, 3, 7, 3),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                  fontSize: dense ? 11 : 11.5,
                  height: 1.15,
                  letterSpacing: 0.02,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum AppBadgeTone { primary, success, warning, error, neutral }
