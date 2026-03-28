import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'app_section_card.dart';

class SmartFilterBar extends StatelessWidget {
  const SmartFilterBar({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.children,
    this.footer,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          ),
          if (footer != null) ...[const Gap(8), footer!],
        ],
      ),
    );
  }
}
