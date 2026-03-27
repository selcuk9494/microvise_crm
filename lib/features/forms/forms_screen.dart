import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

class FormsScreen extends StatelessWidget {
  const FormsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 820;

    return AppPageLayout(
      title: 'Formlar',
      subtitle: 'Başvuru, hurda ve devir formlarını yönetin.',
      body: Column(
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Form Merkezi',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Gap(8),
                Text(
                  'Tüm resmi form akışlarını tek yerden açın. Yeni form türlerini aynı yapı ile bu alana ekleyeceğiz.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
                ),
                const Gap(18),
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _FormEntryCard(
                      title: 'Başvuru Formu',
                      description:
                          'KDV4 ve KDV4A çıktıları ile başvuru kayıtlarını yönetin.',
                      icon: Icons.description_rounded,
                      accent: AppTheme.primary,
                      buttonLabel: 'Aç',
                      onTap: () => context.go('/formlar/basvuru'),
                      width: isMobile ? double.infinity : 320,
                    ),
                    _FormEntryCard(
                      title: 'Hurda Formu',
                      description:
                          'Hurda cihaz süreçleri için aynı mantıkta yeni form akışı burada olacak.',
                      icon: Icons.delete_sweep_rounded,
                      accent: const Color(0xFFB45309),
                      buttonLabel: 'Aç',
                      onTap: () => context.go('/formlar/hurda'),
                      width: isMobile ? double.infinity : 320,
                    ),
                    _FormEntryCard(
                      title: 'Devir Formu',
                      description:
                          'Devir işlemleri için form girişi ve çıktı şablonunu bu modülde toplayacağız.',
                      icon: Icons.swap_horiz_rounded,
                      accent: const Color(0xFF0F766E),
                      buttonLabel: 'Aç',
                      onTap: () => context.go('/formlar/devir'),
                      width: isMobile ? double.infinity : 320,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FormEntryCard extends StatelessWidget {
  const _FormEntryCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.accent,
    required this.buttonLabel,
    required this.onTap,
    required this.width,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color accent;
  final String buttonLabel;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: accent, size: 24),
            ),
            const Gap(14),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Gap(8),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
            ),
            const Gap(16),
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
