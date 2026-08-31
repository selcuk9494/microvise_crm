import 'package:flutter/material.dart';

/// Stacks [header] above [body].
///
/// On phones the whole column scrolls as one page, so tall filters cannot
/// push the list off-screen. On wider screens [body] fills leftover height
/// (pass a ListView there).
class AppPhoneScrollColumn extends StatelessWidget {
  const AppPhoneScrollColumn({
    super.key,
    required this.header,
    required this.body,
    this.padding = EdgeInsets.zero,
    this.breakpoint = 700,
    this.bottomSlop = 108,
  });

  final List<Widget> header;
  final Widget Function({required bool nested}) body;
  final EdgeInsets padding;
  final double breakpoint;
  final double bottomSlop;

  static bool isPhone(BuildContext context, {double breakpoint = 700}) =>
      MediaQuery.sizeOf(context).width < breakpoint;

  static ScrollPhysics physicsFor({required bool nested}) => nested
      ? const NeverScrollableScrollPhysics()
      : const AlwaysScrollableScrollPhysics();

  /// Caps [child] on phones so a tall filter/header cannot eat the list.
  static Widget capHeader({
    required BuildContext context,
    required Widget child,
    double fraction = 0.4,
  }) {
    if (!isPhone(context)) return child;
    final maxHeight = MediaQuery.sizeOf(context).height * fraction;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nested = MediaQuery.sizeOf(context).width < breakpoint;
    if (nested) {
      return ListView(
        padding: padding.add(EdgeInsets.only(bottom: bottomSlop)),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [...header, body(nested: true)],
      );
    }
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...header,
          Expanded(child: body(nested: false)),
        ],
      ),
    );
  }
}
