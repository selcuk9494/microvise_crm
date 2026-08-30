import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../customers/customer_detail_screen.dart';
import '../e_invoice/e_invoice_whatsapp_share.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';

final hatLisansInvoicePaymentFilterProvider =
    NotifierProvider<HatLisansInvoicePaymentFilterNotifier, String>(
      HatLisansInvoicePaymentFilterNotifier.new,
    );

class HatLisansInvoicePaymentFilterNotifier extends Notifier<String> {
  @override
  String build() => 'pending';

  void set(String value) => state = value;
}

final hatLisansInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>((
  ref,
) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return const [];
  final payment = ref.watch(hatLisansInvoicePaymentFilterProvider);
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'hat_lisans_invoices',
      if (payment.isNotEmpty) 'payment': payment,
    },
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(Invoice.fromJson)
      .toList(growable: false);
});

class HatLisansInvoiceCustomer {
  const HatLisansInvoiceCustomer({
    required this.customerId,
    required this.customerName,
    required this.linesTotal,
    required this.gmp3Total,
    required this.irestoTotal,
  });

  final String customerId;
  final String customerName;
  final int linesTotal;
  final int gmp3Total;
  final int irestoTotal;
}

NumberFormat _money(String currency) {
  return NumberFormat.currency(
    locale: 'tr_TR',
    symbol: currency.toUpperCase() == 'USD'
        ? r'$'
        : currency.toUpperCase() == 'EUR'
        ? '€'
        : '₺',
    decimalDigits: 2,
  );
}

Future<void> showCreateHatLisansInvoiceDialog({
  required BuildContext context,
  required WidgetRef ref,
  required List<HatLisansInvoiceCustomer> customers,
  String? singleCustomerId,
}) async {
  final targets = singleCustomerId == null
      ? customers
      : customers.where((e) => e.customerId == singleCustomerId).toList();
  if (targets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fatura oluşturulacak müşteri yok.')),
    );
    return;
  }

  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return;

  Map<String, dynamic> catalog = const {};
  try {
    catalog = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'hat_lisans_billing_catalog'},
    );
  } catch (_) {}
  if (!context.mounted) return;

  double catalogPrice(String key) {
    final row = catalog[key];
    if (row is Map) {
      return (row['sale_price'] as num?)?.toDouble() ?? 0;
    }
    return 0;
  }

  final gprs = TextEditingController(
    text: catalogPrice('gprs') == 0 ? '' : catalogPrice('gprs').toString(),
  );
  final gmp3 = TextEditingController(
    text: catalogPrice('gmp3') == 0 ? '' : catalogPrice('gmp3').toString(),
  );
  final iresto = TextEditingController(
    text: catalogPrice('gmp3') == 0 ? '' : catalogPrice('gmp3').toString(),
  );

  final hatCount = targets.fold<int>(0, (sum, e) => sum + e.linesTotal);
  final gmp3Count = targets.fold<int>(0, (sum, e) => sum + e.gmp3Total);
  final irestoCount = targets.fold<int>(0, (sum, e) => sum + e.irestoTotal);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Hat & Lisans faturası'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              singleCustomerId == null
                  ? '${targets.length} müşteri için taslak fatura oluşacak. '
                        'Her müşterideki hat / GMP3 / iResto adedi kalem miktarı olur.'
                  : '${targets.first.customerName}: Hat ${targets.first.linesTotal} · '
                        'GMP3 ${targets.first.gmp3Total} · iResto ${targets.first.irestoTotal}',
            ),
            const Gap(8),
            Text(
              'Kalemler: Gprs Data ($hatCount) ve Gmp3 Yazarkasa Entegrasyonu '
              '(GMP3 $gmp3Count, iResto $irestoCount). '
              'Ödeme yapılana kadar satış faturası olmaz; Maliye gönderiminden sonra kapanır.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
            ),
            const Gap(12),
            TextField(
              controller: gprs,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Gprs Data birim fiyatı',
              ),
            ),
            const Gap(8),
            TextField(
              controller: gmp3,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Gmp3 Yazarkasa Entegrasyonu birim fiyatı',
              ),
            ),
            const Gap(8),
            TextField(
              controller: iresto,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'iResto birim fiyatı',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Fatura Oluştur'),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    gprs.dispose();
    gmp3.dispose();
    iresto.dispose();
    return;
  }
  if (!context.mounted) return;

  try {
    final response = await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'createHatLisansInvoices',
        'customerIds': targets.map((e) => e.customerId).toList(),
        'prices': {
          'lineUnitPrice': gprs.text.trim(),
          'gmp3UnitPrice': gmp3.text.trim(),
          'irestoUnitPrice': iresto.text.trim(),
        },
      },
      timeout: const Duration(seconds: 120),
    );
    final created = (response['createdCount'] as num?)?.toInt() ?? 0;
    final skipped = (response['skippedCount'] as num?)?.toInt() ?? 0;
    ref.invalidate(hatLisansInvoicesProvider);
    if (!context.mounted) return;
    final tab = DefaultTabController.maybeOf(context);
    if (tab != null && tab.length > 4) {
      tab.animateTo(4);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Taslak fatura: $created'
          '${skipped == 0 ? '' : ' • Atlanan $skipped'}',
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fatura oluşturulamadı: $e')));
    }
  } finally {
    gprs.dispose();
    gmp3.dispose();
    iresto.dispose();
  }
}

class HatLisansInvoicesTab extends ConsumerWidget {
  const HatLisansInvoicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payment = ref.watch(hatLisansInvoicePaymentFilterProvider);
    final invoicesAsync = ref.watch(hatLisansInvoicesProvider);
    final items = invoicesAsync.asData?.value ?? const <Invoice>[];

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final filter = SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'pending',
                      label: Text('Ödeme bekleyen'),
                    ),
                    ButtonSegment(value: 'paid', label: Text('Ödenenler')),
                  ],
                  selected: {payment},
                  onSelectionChanged: (value) {
                    ref
                        .read(hatLisansInvoicePaymentFilterProvider.notifier)
                        .set(value.first);
                  },
                );
                if (constraints.maxWidth < 720) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      filter,
                      const Gap(8),
                      Text(
                        'Bu sekmedeki faturalar taslaktır. Ödeme sonrası satış '
                        'faturasına döner; Maliye gönderimiyle kapanır.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    filter,
                    const Gap(12),
                    Expanded(
                      child: Text(
                        'Taslak faturalar E-Fatura listesine satış olarak düşmez. '
                        'Ödeme + Maliye gönderimi sonrası kapanır.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    AppBadge(
                      label: '${items.length}',
                      tone: AppBadgeTone.neutral,
                      dense: true,
                    ),
                  ],
                );
              },
            ),
          ),
          const Gap(8),
          Expanded(
            child: invoicesAsync.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(
                    child: Text('Bu listede fatura yok.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Gap(8),
                  itemBuilder: (context, index) {
                    return _HatLisansInvoiceRow(invoice: rows[index]);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Yüklenemedi: $error')),
            ),
          ),
        ],
      ),
    );
  }
}

class _HatLisansInvoiceRow extends ConsumerStatefulWidget {
  const _HatLisansInvoiceRow({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_HatLisansInvoiceRow> createState() =>
      _HatLisansInvoiceRowState();
}

class _HatLisansInvoiceRowState extends ConsumerState<_HatLisansInvoiceRow> {
  bool _busy = false;

  String _statusLabel(Invoice invoice) {
    if (invoice.isEInvoiceClosed && invoice.remainingAmount <= 0.009) {
      return 'Kapandı';
    }
    if (invoice.remainingAmount <= 0.009) {
      return invoice.status == 'paid' ? 'Ödendi' : 'Ödendi · Maliye bekliyor';
    }
    if (invoice.status == 'draft') return 'Taslak · ödeme bekliyor';
    if (invoice.status == 'partial') return 'Kısmi ödeme';
    return 'Satış · ödeme bekliyor';
  }

  AppBadgeTone _statusTone(Invoice invoice) {
    if (invoice.isEInvoiceClosed && invoice.remainingAmount <= 0.009) {
      return AppBadgeTone.success;
    }
    if (invoice.remainingAmount <= 0.009) return AppBadgeTone.warning;
    if (invoice.status == 'draft') return AppBadgeTone.neutral;
    return AppBadgeTone.primary;
  }

  Future<void> _withBusy(Future<void> Function() run) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await run();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mailLink() async {
    final invoice = widget.invoice;
    if (!invoice.isHatLisansPayable) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    var email = (invoice.customerEmail ?? '').trim();
    if (!email.contains('@')) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mail ile ödeme linki'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-posta'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Gönder'),
            ),
          ],
        ),
      );
      email = controller.text.trim();
      controller.dispose();
      if (ok != true || !email.contains('@')) return;
    }
    await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'sendInvoicePaymentLinkEmail',
        'invoiceIds': [invoice.id],
        'email': email,
      },
    );
    ref.invalidate(hatLisansInvoicesProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ödeme linki maili gönderildi.')));
  }

  Future<void> _whatsAppLink() async {
    final invoice = widget.invoice;
    if (!invoice.isHatLisansPayable) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final response = await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'createInvoicePaymentLink',
        'invoiceIds': [invoice.id],
      },
    );
    final paymentUrl = response['paymentUrl']?.toString() ?? '';
    if (paymentUrl.isEmpty) {
      throw Exception('Ödeme linki alınamadı');
    }
    CustomerDetail? customer;
    try {
      customer = await ref.read(
        customerDetailProvider(invoice.customerId).future,
      );
    } catch (_) {}
    if (!mounted) return;
    ref.invalidate(hatLisansInvoicesProvider);
    await shareInvoicePaymentLinkWithWhatsApp(
      context: context,
      paymentUrl: paymentUrl,
      amountLabel: _money(invoice.currency).format(invoice.remainingAmount),
      invoiceLabels: [formatInvoiceNumberForDisplay(invoice.invoiceNumber)],
      customerName: invoice.customerName,
      customer: customer,
    );
  }

  Future<void> _copyLink() async {
    final invoice = widget.invoice;
    if (!invoice.isHatLisansPayable) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final response = await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'createInvoicePaymentLink',
        'invoiceIds': [invoice.id],
      },
    );
    final paymentUrl = response['paymentUrl']?.toString() ?? '';
    if (paymentUrl.isEmpty) {
      throw Exception('Ödeme linki alınamadı');
    }
    await Clipboard.setData(ClipboardData(text: paymentUrl));
    ref.invalidate(hatLisansInvoicesProvider);
    ref.invalidate(invoicesProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ödeme linki kopyalandı.')));
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final money = _money(invoice.currency);
    final items = invoice.items;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invoice.customerName?.trim().isNotEmpty == true
                      ? invoice.customerName!
                      : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.text,
                  ),
                ),
              ),
              AppBadge(
                label: _statusLabel(invoice),
                tone: _statusTone(invoice),
                dense: true,
              ),
            ],
          ),
          const Gap(4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              AppBadge(
                label: formatInvoiceNumberForDisplay(invoice.invoiceNumber),
                tone: AppBadgeTone.neutral,
                dense: true,
              ),
              AppBadge(
                label: money.format(invoice.grandTotal),
                tone: AppBadgeTone.primary,
                dense: true,
              ),
              if (invoice.remainingAmount > 0.009)
                AppBadge(
                  label: 'Kalan ${money.format(invoice.remainingAmount)}',
                  tone: AppBadgeTone.warning,
                  dense: true,
                ),
              for (final item in items.take(3))
                AppBadge(
                  label:
                      '${item.description} × ${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)}',
                  tone: AppBadgeTone.neutral,
                  dense: true,
                ),
            ],
          ),
          if (invoice.isHatLisansPayable) ...[
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _withBusy(_copyLink),
                  icon: const Icon(LucideIcons.link, size: 16),
                  label: const Text('Ödeme linki'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _withBusy(_mailLink),
                  icon: const Icon(LucideIcons.mail, size: 16),
                  label: const Text('Mail'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _withBusy(_whatsAppLink),
                  icon: const Icon(LucideIcons.messageCircle, size: 16),
                  label: const Text('WhatsApp'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
