import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/link.dart';

/// Left-click uses in-app routing; the real href keeps native
/// “Open link in new tab” on right-click.
class FinanceOpenLink extends StatelessWidget {
  const FinanceOpenLink({
    super.key,
    required this.location,
    required this.child,
    this.onTap,
  });

  final String location;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(location);
    return Link(
      uri: uri,
      builder: (context, _) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap ?? () => context.go(location),
          child: child,
        );
      },
    );
  }
}
