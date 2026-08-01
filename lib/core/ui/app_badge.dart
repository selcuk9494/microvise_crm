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
    final fg = AppTheme.softFg(color);

    return Container(
      padding: dense
          ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.softTint(color, alpha: AppTheme.isDark ? 0.18 : 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.softBorder(color, alpha: AppTheme.isDark ? 0.32 : 0.24),
        ),
      ),
      child: Text(
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
    );
  }
}

enum AppBadgeTone { primary, success, warning, error, neutral }
