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
    // Option C: identical slate chip; meaning only via left rail + quiet text.
    final fg = Color.alphaBlend(
      color.withValues(alpha: AppTheme.isDark ? 0.55 : 0.72),
      AppTheme.textSoft,
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppTheme.isDark
            ? AppTheme.surfaceSoft
            : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(
          color: AppTheme.border.withValues(
            alpha: AppTheme.isDark ? 0.72 : 0.9,
          ),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: color.withValues(alpha: 0.85)),
            Padding(
              padding: dense
                  ? const EdgeInsets.fromLTRB(6, 2, 6, 2)
                  : const EdgeInsets.fromLTRB(7, 3, 7, 3),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: fg,
                  fontSize: dense ? 10.5 : 11,
                  height: 1.15,
                  letterSpacing: 0.05,
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
