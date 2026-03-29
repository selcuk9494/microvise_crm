import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';
import 'serial_inventory.dart';

class StockScreen extends ConsumerStatefulWidget {
  const StockScreen({super.key});

  @override
  ConsumerState<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends ConsumerState<StockScreen> {
  final _money = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context) {
    final stockAsync = ref.watch(stockLevelsProvider);
    final serialSummaryAsync = ref.watch(productSerialInventorySummaryProvider);

    return AppPageLayout(
      title: 'Stok Durumu',
      subtitle: 'Ürün stok seviyeleri ve hareketleri',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(stockLevelsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _showAdjustmentDialog(context),
          icon: const Icon(Icons.tune_rounded, size: 18),
          label: const Text('Stok Düzeltme'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _showSerialEntryDialog(context),
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: const Text('Seri Stok Girişi'),
        ),
      ],
      body: stockAsync.when(
        data: (stocks) {
          if (stocks.isEmpty) {
            return Center(
              child: AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_rounded,
                        size: 48,
                        color: const Color(0xFF94A3B8),
                      ),
                      const Gap(12),
                      Text(
                        'Stok takipli ürün bulunmuyor',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      const Gap(8),
                      Text(
                        'Ürün tanımlarken "Stok Takibi" seçeneğini aktif edin.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          final serialSummary = serialSummaryAsync.asData?.value ?? const {};
          final totalAvailableSerials = serialSummary.values.fold<int>(
            0,
            (sum, item) => sum + item.availableCount,
          );

          // Separate low stock items
          final lowStock = stocks
              .where((s) => (s.currentStock ?? 0) <= s.minStock)
              .toList();
          final normalStock = stocks
              .where((s) => (s.currentStock ?? 0) > s.minStock)
              .toList();

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            children: [
              // Summary Cards
              Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      title: 'Toplam Ürün',
                      value: stocks.length.toString(),
                      icon: Icons.inventory_2_rounded,
                      color: AppTheme.primary,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Kritik Stok',
                      value: lowStock.length.toString(),
                      icon: Icons.warning_rounded,
                      color: lowStock.isEmpty
                          ? AppTheme.success
                          : AppTheme.error,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: _SummaryCard(
                      title: 'Hazır Seri',
                      value: totalAvailableSerials.toString(),
                      icon: Icons.qr_code_2_rounded,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
              const Gap(16),
              // Low Stock Section
              if (lowStock.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: AppTheme.error),
                      const Gap(10),
                      Expanded(
                        child: Text(
                          'Kritik Stok Seviyesi - ${lowStock.length} ürün',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppTheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                ...lowStock.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StockCard(
                      product: p,
                      money: _money,
                      isLowStock: true,
                      serialSummary: serialSummary[p.id],
                    ),
                  ),
                ),
                const Gap(8),
              ],
              // Normal Stock
              if (normalStock.isNotEmpty) ...[
                Text(
                  'Stok Durumu',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Gap(12),
                ...normalStock.map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StockCard(
                      product: p,
                      money: _money,
                      isLowStock: false,
                      serialSummary: serialSummary[p.id],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text(
            'Stok bilgileri yüklenemedi',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }

  Future<void> _showAdjustmentDialog(BuildContext context) async {
    final stocksAsync = ref.read(stockLevelsProvider);
    final stocks = stocksAsync.value ?? [];
    if (stocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stok takipli ürün bulunmuyor')),
      );
      return;
    }

    String? selectedProductId;
    final quantityController = TextEditingController();
    String adjustmentType = 'in'; // in, out, adjustment
    final notesController = TextEditingController();
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Stok Düzeltme'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedProductId,
                items: stocks
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(
                          '${p.name} (Stok: ${p.currentStock?.toStringAsFixed(0) ?? 0})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => selectedProductId = v),
                decoration: const InputDecoration(labelText: 'Ürün'),
              ),
              const Gap(12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'in', label: Text('Giriş')),
                  ButtonSegment(value: 'out', label: Text('Çıkış')),
                  ButtonSegment(value: 'adjustment', label: Text('Düzeltme')),
                ],
                selected: {adjustmentType},
                onSelectionChanged: (s) =>
                    setState(() => adjustmentType = s.first),
              ),
              const Gap(12),
              TextField(
                controller: quantityController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: adjustmentType == 'adjustment'
                      ? 'Yeni Miktar'
                      : 'Miktar',
                ),
              ),
              const Gap(12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'Açıklama'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (selectedProductId == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ürün seçin')),
                        );
                        return;
                      }

                      final qty = double.tryParse(
                        quantityController.text.replaceAll(',', '.'),
                      );
                      if (qty == null || qty < 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Geçerli bir miktar girin'),
                          ),
                        );
                        return;
                      }

                      setState(() => saving = true);
                      final client = ref.read(supabaseClientProvider);
                      if (client == null) return;

                      try {
                        double adjustedQty = qty;

                        // For adjustment type, calculate the difference
                        if (adjustmentType == 'adjustment') {
                          final currentProduct = stocks.firstWhere(
                            (p) => p.id == selectedProductId,
                          );
                          final currentStock = currentProduct.currentStock ?? 0;
                          adjustedQty = qty - currentStock;
                        }

                        await client.from('stock_movements').insert({
                          'product_id': selectedProductId,
                          'movement_type': adjustmentType == 'adjustment'
                              ? 'adjustment'
                              : adjustmentType,
                          'quantity': adjustedQty.abs(),
                          'reference_type': 'adjustment',
                          'notes': notesController.text.trim().isEmpty
                              ? null
                              : notesController.text.trim(),
                          'created_by': client.auth.currentUser?.id,
                        });

                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      ref.invalidate(stockLevelsProvider);
    }
  }

  Future<void> _showSerialEntryDialog(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final stocksAsync = ref.read(stockLevelsProvider);
    final stocks = stocksAsync.value ?? [];
    if (stocks.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Seri stok için önce stok takipli ürün oluşturun')),
      );
      return;
    }

    String? selectedProductId;
    final serialsController = TextEditingController();
    final notesController = TextEditingController();
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Seri Stok Girişi'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedProductId,
                  items: stocks
                      .map(
                        (p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(
                            p.code?.trim().isNotEmpty ?? false
                                ? '${p.code} - ${p.name}'
                                : p.name,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() => selectedProductId = value),
                  decoration: const InputDecoration(labelText: 'Ürün'),
                ),
                const Gap(12),
                TextField(
                  controller: serialsController,
                  minLines: 7,
                  maxLines: 10,
                  decoration: const InputDecoration(
                    labelText: 'Sicil Numaraları',
                    hintText:
                        'Her sicil numarasını alt alta veya virgülle girin',
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama',
                    hintText: 'İsteğe bağlı not',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final productId = selectedProductId?.trim();
                      if (productId == null || productId.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ürün seçin')),
                        );
                        return;
                      }

                      final serialNumbers = serialsController.text
                          .split(RegExp(r'[\n,;]+'))
                          .map((item) => item.trim().toUpperCase())
                          .where((item) => item.isNotEmpty)
                          .toSet()
                          .toList(growable: false);
                      if (serialNumbers.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('En az bir sicil numarası girin'),
                          ),
                        );
                        return;
                      }

                      setState(() => saving = true);
                      final client = ref.read(supabaseClientProvider);
                      if (client == null) return;

                      try {
                        final userId = client.auth.currentUser?.id;
                        await client.from('product_serial_inventory').insert(
                          serialNumbers
                              .map(
                                (serial) => {
                                  'product_id': productId,
                                  'serial_number': serial,
                                  'notes': notesController.text.trim().isEmpty
                                      ? null
                                      : notesController.text.trim(),
                                  'created_by': userId,
                                },
                              )
                              .toList(growable: false),
                        );
                        await client.from('stock_movements').insert({
                          'product_id': productId,
                          'movement_type': 'in',
                          'quantity': serialNumbers.length.toDouble(),
                          'reference_type': 'serial_inventory',
                          'notes': notesController.text.trim().isEmpty
                              ? 'Toplu seri stok girişi'
                              : notesController.text.trim(),
                          'created_by': userId,
                        });
                        if (context.mounted) Navigator.of(context).pop(true);
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Seri stok kaydedilemedi: $error')),
                        );
                        setState(() => saving = false);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      ref.invalidate(stockLevelsProvider);
      ref.invalidate(productSerialInventorySummaryProvider);
      messenger.showSnackBar(
        const SnackBar(content: Text('Seri stok girişleri kaydedildi.')),
      );
    }
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const Gap(14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
              ),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StockCard extends StatelessWidget {
  const _StockCard({
    required this.product,
    required this.money,
    required this.isLowStock,
    this.serialSummary,
  });

  final Product product;
  final NumberFormat money;
  final bool isLowStock;
  final ProductSerialInventorySummary? serialSummary;

  @override
  Widget build(BuildContext context) {
    final current = product.currentStock ?? 0;
    final min = product.minStock;
    final percentage = min > 0 ? (current / min).clamp(0.0, 2.0) / 2 : 1.0;

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isLowStock
                  ? AppTheme.error.withValues(alpha: 0.1)
                  : AppTheme.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isLowStock ? Icons.warning_rounded : Icons.check_circle_rounded,
              color: isLowStock ? AppTheme.error : AppTheme.success,
              size: 22,
            ),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Gap(4),
                Row(
                  children: [
                    Text(
                      'Min: ${money.format(min)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const Gap(12),
                    if (product.code != null)
                      Text(
                        product.code!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF94A3B8),
                          fontFamily: 'monospace',
                        ),
                      ),
                    if (serialSummary != null) ...[
                      const Gap(12),
                      Text(
                        'Seri: ${serialSummary!.availableCount} hazır / ${serialSummary!.consumedCount} kullanıldı',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ],
                ),
                const Gap(8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percentage,
                    backgroundColor: const Color(0xFFE2E8F0),
                    color: isLowStock ? AppTheme.error : AppTheme.success,
                  ),
                ),
              ],
            ),
          ),
          const Gap(14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money.format(current),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isLowStock ? AppTheme.error : null,
                ),
              ),
              Text(
                'adet',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
