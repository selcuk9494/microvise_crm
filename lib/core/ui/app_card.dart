import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
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
              borderRadius: const BorderRadius.all(Radius.circular(16)),
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
          clickable && _hovered ? -2 : 0,
          0,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color ?? AppTheme.surface,
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          border: Border.all(
            color: clickable && _hovered
                ? AppTheme.primary.withValues(alpha: 0.24)
                : AppTheme.border,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryDark.withValues(alpha: 0.05),
              blurRadius: clickable && _hovered ? 18 : 12,
              offset: Offset(0, clickable && _hovered ? 10 : 6),
            ),
          ],
        ),
        child: content,
      ),
    );
  }
}
