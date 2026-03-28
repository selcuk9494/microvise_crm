import 'package:flutter/material.dart';

import '../../app/theme/app_theme.dart';

class AppPageLayout extends StatelessWidget {
  const AppPageLayout({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.actions,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final horizontalPadding = width >= 1200
        ? 24.0
        : width >= 720
        ? 18.0
        : 12.0;
    final topPadding = width >= 720 ? 16.0 : 10.0;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
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
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    topPadding,
                    horizontalPadding,
                    8,
                  ),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: width >= 720 ? 18 : 14,
                      vertical: width >= 720 ? 14 : 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: isMobile
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (subtitle != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    subtitle!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: AppTheme.textMuted),
                                  ),
                                ),
                              if (actions != null) ...[
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: actions!,
                                ),
                              ],
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    if (subtitle != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          subtitle!,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                color: AppTheme.textMuted,
                                                fontSize: 14,
                                              ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (actions != null)
                                Flexible(
                                  child: Align(
                                    alignment: Alignment.topRight,
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.end,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: actions!,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  8,
                  horizontalPadding,
                  18,
                ),
                sliver: SliverToBoxAdapter(child: body),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
