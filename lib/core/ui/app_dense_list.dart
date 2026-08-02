import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';

/// Shared density tokens for list/table rows across CRM screens.
class AppDenseList {
  static const double rowV = 6;
  static const double rowH = 8;
  static const double headerH = 38;
  static const double leading = 28;

  /// Tap target for dense row action buttons (send / PDF / edit / ⋯).
  static const double action = 32;

  /// Glyph size inside [action] buttons (outlined icons need a touch more size).
  static const double actionIcon = 18;
  static const double listGap = 8;
  static const double metaGap = 6;
  static const double rowHeight = 46;
  static const EdgeInsets cardPadding = EdgeInsets.fromLTRB(12, 10, 12, 10);
  static const EdgeInsets cardPaddingMobile = EdgeInsets.fromLTRB(10, 9, 10, 9);

  static BorderSide get hairline =>
      BorderSide(color: AppTheme.border.withValues(alpha: 0.88), width: 1);

  /// Alternating row fill so list lines stay visually distinct.
  static Color rowFill(int index, {bool selected = false}) {
    if (selected) {
      return AppTheme.softTint(AppTheme.primary, alpha: 0.12);
    }
    return index.isOdd
        ? AppTheme.surfaceMuted.withValues(alpha: 0.55)
        : AppTheme.surface;
  }
}

/// Fixed invoice-table columns — only the customer cell expands.
/// Prevents middle-column "kayma" when row content widths differ.
class AppInvoiceTableCols {
  static const double check = 32;
  static const double date = 82;
  static const double type = 44;
  // Status holds invoice + e-invoice + Akınsoft badges side-by-side.
  static const double status = 268;
  static const double amount = 100;
  // Actions: send + PDF + ERP + edit + overflow (tight gaps).
  static const double actions = 196;
  static const double leadingGap = 6;

  static double get fixedTotal =>
      check + date + type + status + amount + actions;
}

/// Compact leading icon well for dense list rows.
class AppDenseLeadingIcon extends StatelessWidget {
  const AppDenseLeadingIcon({
    super.key,
    required this.icon,
    required this.color,
    this.active = true,
  });

  final IconData icon;
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final fg = active ? AppTheme.softFg(color) : AppTheme.textMuted;
    return Container(
      width: AppDenseList.leading,
      height: AppDenseList.leading,
      decoration: BoxDecoration(
        color: active
            ? AppTheme.softTint(color, alpha: 0.16)
            : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
      ),
      child: Icon(icon, size: 18, color: fg),
    );
  }
}

/// Always-horizontal badge strip — never stacks (avoids tall rows).
class AppDenseBadgeRow extends StatelessWidget {
  const AppDenseBadgeRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Gap(4),
            Flexible(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// Compact meta/info chip used in form list cards.
class AppDenseInfoChip extends StatelessWidget {
  const AppDenseInfoChip({
    super.key,
    required this.icon,
    required this.text,
    this.color,
  });

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.softTint(tone, alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.softBorder(tone, alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.softFg(tone)),
          const Gap(4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.softFg(tone),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dense form/list record card: title row + horizontal meta + action strip.
class AppDenseListCard extends StatelessWidget {
  const AppDenseListCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.badge,
    this.meta = const [],
    this.actions = const [],
    this.onTap,
    this.titleStruck = false,
  });

  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? badge;
  final List<Widget> meta;
  final List<Widget> actions;
  final VoidCallback? onTap;
  final bool titleStruck;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 900;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
        child: Container(
          padding: isMobile
              ? AppDenseList.cardPaddingMobile
              : AppDenseList.cardPadding,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(color: AppTheme.border.withValues(alpha: 0.88)),
            boxShadow: AppTheme.cardShadow,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  leading,
                  const Gap(8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                height: 1.2,
                                decoration: titleStruck
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                              ),
                        ),
                        if ((subtitle ?? '').trim().isNotEmpty)
                          Text(
                            subtitle!.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontSize: 11, height: 1.2),
                          ),
                      ],
                    ),
                  ),
                  if (badge != null) ...[const Gap(8), badge!],
                ],
              ),
              if (meta.isNotEmpty) ...[
                const Gap(6),
                SizedBox(
                  height: 22,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < meta.length; i++) ...[
                        if (i > 0) const Gap(AppDenseList.metaGap),
                        meta[i],
                      ],
                    ],
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const Gap(6),
                SizedBox(
                  height: AppDenseList.action,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const Gap(4),
                        actions[i],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
