import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/app_section_card.dart';

class FormsScreen extends StatelessWidget {
  const FormsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 820;

    return AppPageLayout(
      title: 'Formlar',
      subtitle: 'Başvuru, hurda ve devir formlarını yönetin.',
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          AppSectionCard(
            title: 'Form Merkezi',
            subtitle:
                'Resmi form akışlarını tek merkezden yönetin ve yazdırın.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Gap(4),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _FormEntryCard(
                      title: 'Başvuru Formu',
                      description:
                          'KDV4 ve KDV4A çıktıları ile başvuru kayıtlarını yönetin.',
                      icon: LucideIcons.fileText,
                      accent: AppTheme.primary,
                      buttonLabel: 'Aç',
                      onTap: () => context.go('/formlar/basvuru'),
                      width: isMobile ? double.infinity : 320,
                    ),
                    _FormEntryCard(
                      title: 'Hurda Formu',
                      description:
                          'Hurda cihaz süreçleri için aynı mantıkta yeni form akışı burada olacak.',
                      icon: LucideIcons.trash,
                      accent: AppTheme.warning,
                      buttonLabel: 'Aç',
                      onTap: () => context.go('/formlar/hurda'),
                      width: isMobile ? double.infinity : 320,
                    ),
                    _FormEntryCard(
                      title: 'Devir Formu',
                      description:
                          'Devir işlemleri için form girişi ve çıktı şablonunu bu modülde toplayacağız.',
                      icon: LucideIcons.arrowLeftRight,
                      accent: AppTheme.primary,
                      buttonLabel: 'Aç',
                      onTap: () => context.go('/formlar/devir'),
                      width: isMobile ? double.infinity : 320,
                    ),
                    _FormEntryCard(
                      title: 'Arıza Formu',
                      description:
                          'Arızalı cihaz kayıtlarını ve servis yönlendirme sürecini yönetin.',
                      icon: LucideIcons.circleGauge,
                      accent: AppTheme.error,
                      buttonLabel: 'Aç',
                      onTap: () => context.go('/formlar/ariza'),
                      width: isMobile ? double.infinity : 320,
                    ),
                    _FormEntryCard(
                      title: 'Seri Takip',
                      description:
                          'Seri numarası bazlı ürün takibini ve durumlarını görüntüleyin.',
                      icon: LucideIcons.qrCode,
                      accent: AppTheme.primary,
                      buttonLabel: 'Aç',
                      onTap: () => context.go('/formlar/seri-takip'),
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
          boxShadow: AppTheme.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: AppTheme.isDark ? 0.18 : 0.10),
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
              child: Icon(
                icon,
                color: AppTheme.categoryIconFg(accent),
                size: 19,
              ),
            ),
            const Gap(10),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Gap(4),
            Text(
              description,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
            ),
            const Gap(10),
            FilledButton.icon(
              onPressed: onTap,
              icon: const Icon(LucideIcons.arrowRight, size: 16),
              label: Text(buttonLabel),
            ),
          ],
        ),
      ),
    );
  }
}
