import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../app/app_config.dart';
import '../../app/theme/app_theme.dart';
import '../../core/ui/app_card.dart';

class SetupRequiredScreen extends StatelessWidget {
  const SetupRequiredScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final configured = AppConfig.isSupabaseConfigured;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Kurulum Gerekli',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Gap(8),
                    Text(
                      configured
                          ? 'Supabase yapılandırması bulundu ama uygulama başlatılamadı.'
                          : 'Uygulamayı çalıştırmak için Supabase URL ve Anon Key gerekli.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF475569)),
                    ),
                    const Gap(20),
                    _KeyRow(
                      label: 'SUPABASE_URL',
                      value: AppConfig.supabaseUrl.isEmpty
                          ? 'Tanımlı değil'
                          : AppConfig.supabaseUrl,
                    ),
                    const Gap(10),
                    _KeyRow(
                      label: 'SUPABASE_ANON_KEY',
                      value: AppConfig.supabaseAnonKey.isEmpty
                          ? 'Tanımlı değil'
                          : '${AppConfig.supabaseAnonKey.substring(0, 10)}…',
                    ),
                    const Gap(20),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Text(
                        'flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              color: const Color(0xFF0F172A),
                            ),
                      ),
                    ),
                    const Gap(16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Supabase değerlerini girip uygulamayı yeniden başlatın.',
                                ),
                              ),
                            ),
                            child: const Text('Anladım'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 170,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0F172A),
                ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF475569)),
          ),
        ),
      ],
    );
  }
}

