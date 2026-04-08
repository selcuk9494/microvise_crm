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
    final isMobile = width < 720;
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
        : width >= 720
        ? AppTheme.pagePaddingTablet.horizontal / 2
        : AppTheme.pagePaddingMobile.horizontal / 2;
    final topPadding =
        width >= 720 ? (widget.compactHeader ? 4.0 : 14.0) : 10.0;

    if (isMobile) {
      final hasExtras = (widget.subtitle?.trim().isNotEmpty ?? false) ||
          (normalizedActions != null && normalizedActions.isNotEmpty);
      final expandedHeight =
          hasExtras ? (widget.compactHeader ? 160.0 : 190.0) : kToolbarHeight;

      return Scaffold(
        backgroundColor: AppTheme.background,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppTheme.backgroundAlt.withValues(alpha: 0.82),
                AppTheme.background,
                AppTheme.background,
              ],
            ),
          ),
          child: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                backgroundColor: AppTheme.background,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                pinned: true,
                floating: false,
                expandedHeight: expandedHeight,
                toolbarHeight: kToolbarHeight,
                titleSpacing: horizontalPadding,
                title: Text(
                  widget.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                flexibleSpace: hasExtras
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxHeight <= kToolbarHeight + 1) {
                            return const SizedBox.shrink();
                          }
                          final t = ((constraints.maxHeight - kToolbarHeight) /
                                  (expandedHeight - kToolbarHeight))
                              .clamp(0.0, 1.0);
                          final opacity = Curves.easeOut.transform(t);

                          return ClipRect(
                            child: SafeArea(
                              bottom: false,
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Opacity(
                                  opacity: opacity,
                                  child: Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      horizontalPadding,
                                      0,
                                      horizontalPadding,
                                      12,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (widget.subtitle != null)
                                          Text(
                                            widget.subtitle!,
                                            maxLines:
                                                widget.compactHeader ? 1 : 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: AppTheme.textMuted,
                                                  fontSize: widget.compactHeader
                                                      ? 12
                                                      : null,
                                                ),
                                          ),
                                        if (normalizedActions != null &&
                                            normalizedActions.isNotEmpty) ...[
                                          SizedBox(
                                            height:
                                                widget.compactHeader ? 8 : 10,
                                          ),
                                          SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: [
                                                for (final w
                                                    in normalizedActions) ...[
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
                                ),
                              ),
                            ),
                          );
                        },
                      )
                    : null,
              ),
            ],
            body: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  10,
                  horizontalPadding,
                  16,
                ),
                child: widget.body,
              ),
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
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.backgroundAlt.withValues(alpha: 0.82),
                  AppTheme.background,
                  AppTheme.background,
                ],
              ),
            ),
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragUpdate: (details) => _scrollBy(details.delta.dy),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      topPadding,
                      horizontalPadding,
                      widget.compactHeader ? 4 : 6,
                    ),
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: width >= 720
                            ? (widget.compactHeader ? 14 : 18)
                            : 14,
                        vertical: width >= 720
                            ? (widget.compactHeader ? 8 : 12)
                            : 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: AppTheme.cardShadow,
                      ),
                      child: isMobile
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                if (widget.subtitle != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      widget.subtitle!,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: AppTheme.textMuted),
                                    ),
                                  ),
                                if (normalizedActions != null) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: normalizedActions,
                                  ),
                                ],
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.title,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              fontSize: widget.compactHeader
                                                  ? 20
                                                  : null,
                                            ),
                                      ),
                                      if (!widget.compactHeader &&
                                          widget.subtitle != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Text(
                                            widget.subtitle!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: AppTheme.textMuted,
                                                  fontSize:
                                                      widget.compactHeader ? 12 : 13,
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
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
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
                    child: widget.body,
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
