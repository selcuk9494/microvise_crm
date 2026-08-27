import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import 'bkm_acquirer_definition.dart';

Future<void> showBkmAcquirersManager(BuildContext context, WidgetRef ref) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _BkmAcquirersManagerDialog(),
  );
}

Future<void> showBkmAcquirerEditor(
  BuildContext context,
  WidgetRef ref, {
  BkmAcquirerDefinition? initial,
  int? presetBkmId,
  String? presetName,
}) async {
  final idController = TextEditingController(
    text: initial != null
        ? '${initial.bkmId}'
        : (presetBkmId != null ? '$presetBkmId' : ''),
  );
  final nameController = TextEditingController(
    text: initial?.name ?? presetName ?? '',
  );
  var saving = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        initial == null ? 'BKM ID Ekle' : 'BKM ID Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(LucideIcons.x),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: idController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'BKM ID',
                    hintText: 'Örn. 12',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Banka adı',
                    hintText: 'Örn. Halk Bankası',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Gap(14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final bkmId = int.tryParse(
                                  idController.text.trim(),
                                );
                                final name = nameController.text.trim();
                                if (bkmId == null ||
                                    bkmId <= 0 ||
                                    name.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Geçerli bir BKM ID ve banka adı girin.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final apiClient = ref.read(apiClientProvider);
                                final client = ref.read(
                                  supabaseClientProvider,
                                );
                                if (apiClient == null && client == null) {
                                  return;
                                }
                                setState(() => saving = true);
                                try {
                                  await _saveBkmAcquirer(
                                    apiClient: apiClient,
                                    client: client,
                                    initial: initial,
                                    bkmId: bkmId,
                                    name: name,
                                  );
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Kaydedilemedi. Bu BKM ID zaten tanımlı olabilir.',
                                      ),
                                    ),
                                  );
                                } finally {
                                  setState(() => saving = false);
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(initial == null ? 'Ekle' : 'Kaydet'),
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
  );

  idController.dispose();
  nameController.dispose();
}

Future<void> _saveBkmAcquirer({
  required ApiClient? apiClient,
  required dynamic client,
  required BkmAcquirerDefinition? initial,
  required int bkmId,
  required String name,
}) async {
  if (apiClient != null) {
    if (initial == null) {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'insertMany',
          'table': 'bkm_acquirers',
          'rows': [
            {'bkm_id': bkmId, 'name': name, 'is_active': true},
          ],
        },
      );
    } else {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'bkm_acquirers',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': initial.id},
          ],
          'values': {'bkm_id': bkmId, 'name': name},
        },
      );
    }
    return;
  }
  if (initial == null) {
    await client.from('bkm_acquirers').insert({
      'bkm_id': bkmId,
      'name': name,
      'is_active': true,
    });
  } else {
    await client
        .from('bkm_acquirers')
        .update({'bkm_id': bkmId, 'name': name})
        .eq('id', initial.id);
  }
}

class _BkmAcquirersManagerDialog extends ConsumerWidget {
  const _BkmAcquirersManagerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(bkmAcquirersProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'BKM ID Tanımları',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      await showBkmAcquirerEditor(context, ref);
                      ref.invalidate(bkmAcquirersProvider);
                    },
                    icon: const Icon(LucideIcons.plus, size: 16),
                    label: const Text('Ekle'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              const Gap(6),
              Text(
                'TSM logundaki AcquirerId değerine göre banka adı gösterilir.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
              const Gap(12),
              Expanded(
                child: itemsAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return Center(
                        child: Text(
                          'Henüz BKM ID yok. Ekle ile tanımlayın.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                      );
                    }
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Gap(8),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceMuted,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Row(
                            children: [
                              AppBadge(
                                label: '${item.bkmId}',
                                tone: AppBadgeTone.primary,
                                dense: true,
                              ),
                              const Gap(10),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Düzenle',
                                onPressed: () async {
                                  await showBkmAcquirerEditor(
                                    context,
                                    ref,
                                    initial: item,
                                  );
                                  ref.invalidate(bkmAcquirersProvider);
                                },
                                icon: const Icon(LucideIcons.pencil, size: 18),
                              ),
                              IconButton(
                                tooltip: 'Sil',
                                onPressed: () async {
                                  await _deleteBkmAcquirer(context, ref, item);
                                },
                                icon: const Icon(LucideIcons.trash2, size: 18),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Center(
                    child: Text('BKM ID listesi yüklenemedi.'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _deleteBkmAcquirer(
  BuildContext context,
  WidgetRef ref,
  BkmAcquirerDefinition item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('BKM ID Sil'),
      content: Text('${item.bkmId} — ${item.name} kaydını silmek istiyor musunuz?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sil'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final apiClient = ref.read(apiClientProvider);
  final client = ref.read(supabaseClientProvider);
  if (apiClient != null) {
    await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'deleteWhere',
        'table': 'bkm_acquirers',
        'filters': [
          {'col': 'id', 'op': 'eq', 'value': item.id},
        ],
      },
    );
  } else if (client != null) {
    await client.from('bkm_acquirers').delete().eq('id', item.id);
  }
  ref.invalidate(bkmAcquirersProvider);
}
