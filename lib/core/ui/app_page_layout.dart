import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';

class AppPageLayout extends StatefulWidget {
  const AppPageLayout({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.actions,
    this.compactHeader = false,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;
  final bool compactHeader;

  @override
  State<AppPageLayout> createState() => _AppPageLayoutState();
}

class _AppPageLayoutState extends State<AppPageLayout> {
  final ScrollController _primaryScrollController = ScrollController();

  @override
  void dispose() {
    _primaryScrollController.dispose();
    super.dispose();
  }

  void _scrollBy(double deltaDy) {
    if (!_primaryScrollController.hasClients) return;
    final position = _primaryScrollController.position;
    final next = (position.pixels - deltaDy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (next == position.pixels) return;
    _primaryScrollController.jumpTo(next);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 560;
    final normalizedActions = widget.actions
        ?.map(
          (widget) => widget is Gap
              ? SizedBox(
                  width: widget.mainAxisExtent,
                  height: widget.mainAxisExtent,
                )
              : widget,
        )
        .toList(growable: false);
    final horizontalPadding = width >= 1200
        ? AppTheme.pagePaddingDesktop.horizontal / 2
        : width >= 560
        ? AppTheme.pagePaddingTablet.horizontal / 2
        : AppTheme.pagePaddingMobile.horizontal / 2;
    final topPadding = width >= 560
        ? (widget.compactHeader ? 2.0 : 10.0)
        : 10.0;

    if (isMobile) {
      final hasSubtitle = widget.subtitle?.trim().isNotEmpty ?? false;
      final hasActions =
          normalizedActions != null && normalizedActions.isNotEmpty;
      final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: -0.3,
      );
      final subtitleStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppTheme.textMuted,
        height: 1.35,
        fontSize: widget.compactHeader ? 12.5 : 13.5,
      );

      // Fixed column header — avoids SliverAppBar title/flexibleSpace overlap
      // on notched phones (title stacking on subtitle).
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: DecoratedBox(
          decoration: AppTheme.pageCanvas,
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.98),
                    border: Border(
                      bottom: BorderSide(
                        color: AppTheme.border.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    widget.compactHeader ? 10 : 14,
                    horizontalPadding,
                    widget.compactHeader ? 12 : 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      if (hasSubtitle) ...[
                        SizedBox(height: widget.compactHeader ? 5 : 6),
                        Text(
                          widget.subtitle!,
                          maxLines: widget.compactHeader ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: subtitleStyle,
                        ),
                      ],
                      if (hasActions) ...[
                        SizedBox(height: widget.compactHeader ? 10 : 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final w in normalizedActions) ...[
                                w,
                                const SizedBox(width: 10),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      12,
                      horizontalPadding,
                      16,
                    ),
                    child: widget.body,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: PrimaryScrollController(
          controller: _primaryScrollController,
          child: DecoratedBox(
            decoration: AppTheme.pageCanvas,
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (details) =>
                      _scrollBy(details.delta.dy),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      topPadding,
                      horizontalPadding,
                      widget.compactHeader ? 4 : 6,
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: widget.compactHeader ? 2 : 4,
                        vertical: widget.compactHeader ? 6 : 8,
                      ),
                      child: Row(
                        crossAxisAlignment: widget.compactHeader
                            ? CrossAxisAlignment.center
                            : CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        fontSize: widget.compactHeader
                                            ? 20
                                            : null,
                                      ),
                                ),
                                if (!widget.compactHeader &&
                                    widget.subtitle != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      widget.subtitle!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: AppTheme.textMuted,
                                            fontSize: 13,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (normalizedActions != null)
                            Flexible(
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.end,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: normalizedActions,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      6,
                      horizontalPadding,
                      16,
                    ),
                    child: ClipRect(child: widget.body),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
