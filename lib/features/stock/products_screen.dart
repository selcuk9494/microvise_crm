import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';

class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  String? _categoryFilter;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider(_categoryFilter));

    return AppPageLayout(
      title: 'Ürün/Hizmet Kataloğu',
      subtitle: 'Ürün, hizmet ve yedek parça tanımları',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(productsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _showProductDialog(context, null),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Ürün'),
        ),
      ],
      body: Column(
        children: [
          // Category Filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                _CategoryChip(
                  label: 'Tümü',
                  selected: _categoryFilter == null,
                  onTap: () => setState(() => _categoryFilter = null),
                ),
                const Gap(8),
                _CategoryChip(
                  label: 'Ürünler',
                  selected: _categoryFilter == 'product',
                  onTap: () => setState(() => _categoryFilter = 'product'),
                ),
                const Gap(8),
                _CategoryChip(
                  label: 'Hizmetler',
                  selected: _categoryFilter == 'service',
                  onTap: () => setState(() => _categoryFilter = 'service'),
                ),
                const Gap(8),
                _CategoryChip(
                  label: 'Yedek Parça',
                  selected: _categoryFilter == 'part',
                  onTap: () => setState(() => _categoryFilter = 'part'),
                ),
              ],
            ),
          ),
          const Gap(16),
          // Products List
          Expanded(
            child: productsAsync.when(
              data: (products) {
                // Filter by type if category is set
                var filtered = products;
                if (_categoryFilter != null) {
                  filtered = products.where((p) => p.productType == _categoryFilter).toList();
                }

                if (filtered.isEmpty) {
                  return Center(
                    child: AppCard(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_rounded, size: 48, color: const Color(0xFF94A3B8)),
                            const Gap(12),
                            Text(
                              'Ürün bulunmuyor',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Gap(10),
                  itemBuilder: (context, index) {
                    final product = filtered[index];
                    return _ProductCard(
                      product: product,
                      money: _money,
                      onTap: () => _showProductDialog(context, product),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Text(
                  'Ürünler yüklenemedi',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showProductDialog(BuildContext context, Product? product) async {
    final isEdit = product != null;
    final codeController = TextEditingController(text: product?.code ?? '');
    final nameController = TextEditingController(text: product?.name ?? '');
    final descController = TextEditingController(text: product?.description ?? '');
    final purchasePriceController = TextEditingController(text: product?.purchasePrice.toString() ?? '0');
    final salePriceController = TextEditingController(text: product?.salePrice.toString() ?? '0');
    final minStockController = TextEditingController(text: product?.minStock.toString() ?? '0');
    
    String productType = product?.productType ?? 'product';
    String unit = product?.unit ?? 'Adet';
    double taxRate = product?.taxRate ?? 20;
    bool trackStock = product?.trackStock ?? false;
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(isEdit ? 'Ürün Düzenle' : 'Yeni Ürün'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'product', label: Text('Ürün')),
                    ButtonSegment(value: 'service', label: Text('Hizmet')),
                    ButtonSegment(value: 'part', label: Text('Parça')),
                  ],
                  selected: {productType},
                  onSelectionChanged: (s) => setState(() => productType = s.first),
                ),
                const Gap(16),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(labelText: 'Ürün Kodu'),
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Ürün Adı *'),
                ),
                const Gap(12),
                TextField(
                  controller: descController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Açıklama'),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: purchasePriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Alış Fiyatı'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: TextField(
                        controller: salePriceController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Satış Fiyatı'),
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: unit,
                        items: const [
                          DropdownMenuItem(value: 'Adet', child: Text('Adet')),
                          DropdownMenuItem(value: 'Kg', child: Text('Kg')),
                          DropdownMenuItem(value: 'Lt', child: Text('Lt')),
                          DropdownMenuItem(value: 'Mt', child: Text('Mt')),
                          DropdownMenuItem(value: 'Saat', child: Text('Saat')),
                        ],
                        onChanged: (v) => setState(() => unit = v ?? 'Adet'),
                        decoration: const InputDecoration(labelText: 'Birim'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        value: taxRate,
                        items: const [
                          DropdownMenuItem(value: 0.0, child: Text('%0')),
                          DropdownMenuItem(value: 1.0, child: Text('%1')),
                          DropdownMenuItem(value: 10.0, child: Text('%10')),
                          DropdownMenuItem(value: 20.0, child: Text('%20')),
                        ],
                        onChanged: (v) => setState(() => taxRate = v ?? 20),
                        decoration: const InputDecoration(labelText: 'KDV'),
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: trackStock,
                  onChanged: (v) => setState(() => trackStock = v),
                  title: const Text('Stok Takibi'),
                  subtitle: const Text('Bu ürün için stok miktarı izlensin'),
                ),
                if (trackStock) ...[
                  TextField(
                    controller: minStockController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Minimum Stok'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Ürün adı gerekli')),
                        );
                        return;
                      }

                      setState(() => saving = true);
                      final client = ref.read(supabaseClientProvider);
                      if (client == null) return;

                      try {
                        final data = {
                          'code': codeController.text.trim().isEmpty ? null : codeController.text.trim(),
                          'name': nameController.text.trim(),
                          'description': descController.text.trim().isEmpty ? null : descController.text.trim(),
                          'product_type': productType,
                          'unit': unit,
                          'purchase_price': double.tryParse(purchasePriceController.text) ?? 0,
                          'sale_price': double.tryParse(salePriceController.text) ?? 0,
                          'tax_rate': taxRate,
                          'track_stock': trackStock,
                          'min_stock': double.tryParse(minStockController.text) ?? 0,
                        };

                        if (isEdit) {
                          await client.from('products').update(data).eq('id', product.id);
                        } else {
                          data['created_by'] = client.auth.currentUser?.id;
                          await client.from('products').insert(data);
                        }

                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
                        }
                      }
                    },
              child: saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(isEdit ? 'Güncelle' : 'Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      ref.invalidate(productsProvider);
    }
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      backgroundColor: selected ? AppTheme.primary.withValues(alpha: 0.1) : null,
      side: selected ? BorderSide(color: AppTheme.primary.withValues(alpha: 0.3)) : null,
      onPressed: onTap,
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.money, required this.onTap});

  final Product product;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (typeLabel, typeTone) = switch (product.productType) {
      'product' => ('Ürün', AppBadgeTone.primary),
      'service' => ('Hizmet', AppBadgeTone.success),
      'part' => ('Parça', AppBadgeTone.warning),
      _ => ('?', AppBadgeTone.neutral),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                product.productType == 'service'
                    ? Icons.build_rounded
                    : product.productType == 'part'
                        ? Icons.settings_rounded
                        : Icons.inventory_2_rounded,
                color: AppTheme.primary,
                size: 22,
              ),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (product.code != null) ...[
                        Text(
                          product.code!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: const Color(0xFF64748B),
                                fontFamily: 'monospace',
                              ),
                        ),
                        const Gap(8),
                      ],
                      AppBadge(label: typeLabel, tone: typeTone),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (product.trackStock) ...[
                    const Gap(4),
                    Row(
                      children: [
                        Icon(Icons.inventory_rounded, size: 12, color: const Color(0xFF94A3B8)),
                        const Gap(4),
                        Text(
                          'Stok Takipli',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Gap(12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money.format(product.salePrice),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  '%${product.taxRate.toInt()} KDV',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
