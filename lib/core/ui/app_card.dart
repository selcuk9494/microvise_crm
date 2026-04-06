import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.color,
    this.borderColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final child = Padding(padding: widget.padding, child: widget.child);
    final clickable = widget.onTap != null;

    final content = clickable
        ? Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: const BorderRadius.all(
                Radius.circular(AppTheme.radiusMd),
              ),
              onTap: widget.onTap,
              child: child,
            ),
          )
        : child;

    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        transform: Matrix4.translationValues(
          0,
          clickable && _hovered ? -1.5 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: widget.color ?? Theme.of(context).cardTheme.color ?? AppTheme.surface,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppTheme.radiusMd),
          ),
          border: Border.all(
            color: clickable && _hovered
                ? (widget.borderColor ?? AppTheme.primary).withValues(alpha: 0.55)
                : (widget.borderColor ?? AppTheme.border),
          ),
          boxShadow: clickable && _hovered
              ? AppTheme.hoverShadow
              : AppTheme.cardShadow,
        ),
        child: content,
      ),
    );
  }
}
