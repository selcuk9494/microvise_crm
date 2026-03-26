import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'customers_providers.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  bool _handledCreateQuery = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_handledCreateQuery) return;
    final uri = GoRouterState.of(context).uri;
    final create = uri.queryParameters['yeni'] == '1';
    if (!create) return;

    _handledCreateQuery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.go('/musteriler');
      await _showCreateCustomerDialog(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(customerFiltersProvider);
    final customersAsync = ref.watch(customersProvider);
    final citiesAsync = ref.watch(customerCitiesProvider);

    return AppPageLayout(
      title: 'Müşteriler',
      subtitle: 'Firma kartları ve hızlı filtreleme.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => _showExcelImportDialog(context, ref),
          icon: const Icon(Icons.upload_file_rounded, size: 18),
          label: const Text('Excel İçe Aktar'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _showCreateCustomerDialog(context, ref),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Müşteri'),
        ),
      ],
      body: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Ara',
                      hintText: 'Firma adı',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (v) => ref
                        .read(customerFiltersProvider.notifier)
                        .setSearch(v),
                  ),
                ),
                const Gap(12),
                SizedBox(
                  width: 220,
                  child: citiesAsync.when(
                    data: (cities) => DropdownButtonFormField<String>(
                      value: filters.city,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Tüm Şehirler'),
                        ),
                        ...cities.map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(c),
                          ),
                        ),
                      ],
                      onChanged: (v) => ref
                          .read(customerFiltersProvider.notifier)
                          .setCity(v),
                      decoration: const InputDecoration(
                        labelText: 'Şehir',
                      ),
                    ),
                    loading: () => const _DropdownSkeleton(),
                    error: (_, __) => DropdownButtonFormField<String>(
                      value: filters.city,
                      items: const [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text('Tüm Şehirler'),
                        ),
                      ],
                      onChanged: (v) => ref
                          .read(customerFiltersProvider.notifier)
                          .setCity(v),
                      decoration: const InputDecoration(labelText: 'Şehir'),
                    ),
                  ),
                ),
                const Gap(12),
                OutlinedButton(
                  onPressed: () {
                    ref.read(customerFiltersProvider.notifier).setSearch('');
                    ref.read(customerFiltersProvider.notifier).setCity(null);
                  },
                  child: const Text('Sıfırla'),
                ),
              ],
            ),
          ),
          const Gap(14),
          customersAsync.when(
            data: (customers) {
              if (customers.isEmpty) {
                return AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.18),
                            ),
                          ),
                          child: const Icon(
                            Icons.inbox_rounded,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kayıt bulunamadı',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const Gap(2),
                              Text(
                                'Filtreleri temizleyin veya yeni müşteri ekleyin.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const _HeaderRow(),
                    const Divider(height: 1),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = customers[index];
                        return _CustomerRow(
                          name: c.name,
                          city: c.city,
                          active: c.isActive,
                          activeLineCount: c.activeLineCount,
                          activeGmp3Count: c.activeGmp3Count,
                          onTap: () => context.go('/musteriler/${c.id}'),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
            loading: () => Skeletonizer(
              enabled: true,
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const _HeaderRow(),
                    const Divider(height: 1),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 6,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => const _CustomerRow(
                        name: 'Microvise Teknoloji A.Ş.',
                        city: 'İstanbul',
                        active: true,
                        activeLineCount: 2,
                        activeGmp3Count: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            error: (_, __) => AppCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Müşteriler yüklenemedi. Yetki ve bağlantı ayarlarını kontrol edin.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Firma',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              'Şehir',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
            ),
          ),
          SizedBox(
            width: 280,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Durum / Ürünler',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF475569),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatefulWidget {
  const _CustomerRow({
    required this.name,
    required this.city,
    required this.active,
    required this.activeLineCount,
    required this.activeGmp3Count,
    this.onTap,
  });

  final String name;
  final String? city;
  final bool active;
  final int activeLineCount;
  final int activeGmp3Count;
  final VoidCallback? onTap;

  @override
  State<_CustomerRow> createState() => _CustomerRowState();
}

class _CustomerRowState extends State<_CustomerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final clickable = widget.onTap != null;

    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? const Color(0xFFF8FAFC) : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: widget.active
                              ? TextDecoration.none
                              : TextDecoration.lineThrough,
                        ),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: Text(
                    widget.city ?? '—',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: const Color(0xFF64748B)),
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (widget.activeLineCount > 0) ...[
                          AppBadge(
                            label: 'Hat ${widget.activeLineCount}',
                            tone: AppBadgeTone.primary,
                          ),
                          const Gap(8),
                        ],
                        if (widget.activeGmp3Count > 0) ...[
                          AppBadge(
                            label: 'GMP3 ${widget.activeGmp3Count}',
                            tone: AppBadgeTone.neutral,
                          ),
                          const Gap(8),
                        ],
                        AppBadge(
                          label: widget.active ? 'Aktif' : 'Pasif',
                          tone: widget.active
                              ? AppBadgeTone.success
                              : AppBadgeTone.neutral,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownSkeleton extends StatelessWidget {
  const _DropdownSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: DropdownButtonFormField<String>(
        value: null,
        items: const [
          DropdownMenuItem<String>(value: null, child: Text('Tüm Şehirler')),
        ],
        onChanged: (_) {},
        decoration: const InputDecoration(labelText: 'Şehir'),
      ),
    );
  }
}

Future<void> _showCreateCustomerDialog(BuildContext context, WidgetRef ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Supabase bağlantısı bulunamadı.')),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _CreateCustomerDialog(),
  );

  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);
}

class _CreateCustomerDialog extends ConsumerStatefulWidget {
  const _CreateCustomerDialog();

  @override
  ConsumerState<_CreateCustomerDialog> createState() =>
      _CreateCustomerDialogState();
}

class _CreateCustomerDialogState extends ConsumerState<_CreateCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _cityController = TextEditingController();
  final _emailController = TextEditingController();
  final _vknController = TextEditingController();
  final _notesController = TextEditingController();

  final _phone1TitleController = TextEditingController(text: 'Muhasebe');
  final _phone1Controller = TextEditingController();
  final _phone2TitleController = TextEditingController(text: 'Yetkili');
  final _phone2Controller = TextEditingController();
  final _phone3TitleController = TextEditingController(text: 'Servis');
  final _phone3Controller = TextEditingController();

  final List<_BranchDraft> _branches = [_BranchDraft()];
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _emailController.dispose();
    _vknController.dispose();
    _notesController.dispose();
    _phone1TitleController.dispose();
    _phone1Controller.dispose();
    _phone2TitleController.dispose();
    _phone2Controller.dispose();
    _phone3TitleController.dispose();
    _phone3Controller.dispose();
    for (final b in _branches) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final name = _nameController.text.trim();
      final city = _cityController.text.trim();
      final email = _emailController.text.trim();
      final vkn = _vknController.text.trim();
      final notes = _notesController.text.trim();

      final phone1 = _phone1Controller.text.trim();
      final phone2 = _phone2Controller.text.trim();
      final phone3 = _phone3Controller.text.trim();

      final inserted = await client.from('customers').insert({
        'name': name,
        'city': city.isEmpty ? null : city,
        'email': email.isEmpty ? null : email,
        'vkn': vkn.isEmpty ? null : vkn,
        'notes': notes.isEmpty ? null : notes,
        'phone_1': phone1.isEmpty ? null : phone1,
        'phone_1_title': phone1.isEmpty ? null : _phone1TitleController.text.trim(),
        'phone_2': phone2.isEmpty ? null : phone2,
        'phone_2_title': phone2.isEmpty ? null : _phone2TitleController.text.trim(),
        'phone_3': phone3.isEmpty ? null : phone3,
        'phone_3_title': phone3.isEmpty ? null : _phone3TitleController.text.trim(),
        'is_active': true,
        'created_by': client.auth.currentUser?.id,
      }).select('id').single();

      final customerId = inserted['id'].toString();

      final branchRows = <Map<String, dynamic>>[];
      for (final b in _branches) {
        final row = b.toInsertRow(customerId);
        if (row != null) branchRows.add(row);
      }

      if (branchRows.isNotEmpty) {
        await client.from('branches').insert(branchRows);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Müşteri oluşturuldu.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Müşteri oluşturulamadı.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Yeni Müşteri',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Firma Adı',
                    hintText: 'Örn: Microvise Teknoloji A.Ş.',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 2) return 'Firma adı gerekli.';
                    return null;
                  },
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cityController,
                        decoration: const InputDecoration(
                          labelText: 'Şehir',
                          hintText: 'Örn: İstanbul',
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: TextFormField(
                        controller: _vknController,
                        decoration: const InputDecoration(
                          labelText: 'VKN',
                          hintText: 'Vergi Kimlik No',
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    hintText: 'ornek@firma.com',
                  ),
                ),
                const Gap(12),
                _PhoneRow(
                  titleController: _phone1TitleController,
                  phoneController: _phone1Controller,
                  label: 'Telefon 1',
                ),
                const Gap(12),
                _PhoneRow(
                  titleController: _phone2TitleController,
                  phoneController: _phone2Controller,
                  label: 'Telefon 2',
                ),
                const Gap(12),
                _PhoneRow(
                  titleController: _phone3TitleController,
                  phoneController: _phone3Controller,
                  label: 'Telefon 3',
                ),
                const Gap(12),
                TextFormField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Not',
                    hintText: 'İsteğe bağlı',
                  ),
                ),
                const Gap(16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Şubeler',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Gap(2),
                            Text(
                              'Şube adı, adres ve konum bilgileri ekleyin.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving
                            ? null
                            : () => setState(() => _branches.add(_BranchDraft())),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Şube Ekle'),
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _branches.length,
                    separatorBuilder: (_, __) => const Gap(12),
                    itemBuilder: (context, index) {
                      final b = _branches[index];
                      return _BranchCard(
                        draft: b,
                        index: index,
                        canRemove: _branches.length > 1,
                        onRemove: _saving
                            ? null
                            : () => setState(() {
                                  b.dispose();
                                  _branches.removeAt(index);
                                }),
                      );
                    },
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneRow extends StatelessWidget {
  const _PhoneRow({
    required this.titleController,
    required this.phoneController,
    required this.label,
  });

  final TextEditingController titleController;
  final TextEditingController phoneController;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            controller: titleController,
            decoration: InputDecoration(
              labelText: '$label Görev',
              hintText: 'Örn: Yetkili',
            ),
          ),
        ),
        const Gap(12),
        Expanded(
          flex: 3,
          child: TextFormField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: label,
              hintText: '0 5xx xxx xx xx',
            ),
          ),
        ),
      ],
    );
  }
}

class _BranchDraft {
  final nameController = TextEditingController(text: 'Merkez');
  final cityController = TextEditingController();
  final addressController = TextEditingController();
  final phoneController = TextEditingController();
  final latController = TextEditingController();
  final lngController = TextEditingController();

  void dispose() {
    nameController.dispose();
    cityController.dispose();
    addressController.dispose();
    phoneController.dispose();
    latController.dispose();
    lngController.dispose();
  }

  Map<String, dynamic>? toInsertRow(String customerId) {
    final name = nameController.text.trim();
    final city = cityController.text.trim();
    final address = addressController.text.trim();
    final phone = phoneController.text.trim();
    final lat = double.tryParse(latController.text.trim());
    final lng = double.tryParse(lngController.text.trim());

    if (name.isEmpty && city.isEmpty && address.isEmpty && phone.isEmpty) {
      return null;
    }

    return {
      'customer_id': customerId,
      'name': name.isEmpty ? 'Şube' : name,
      'city': city.isEmpty ? null : city,
      'address': address.isEmpty ? null : address,
      'phone': phone.isEmpty ? null : phone,
      'location_lat': lat,
      'location_lng': lng,
      'is_active': true,
    };
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.draft,
    required this.index,
    required this.canRemove,
    required this.onRemove,
  });

  final _BranchDraft draft;
  final int index;
  final bool canRemove;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Şube ${index + 1}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (canRemove)
                IconButton(
                  tooltip: 'Sil',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
            ],
          ),
          const Gap(10),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.nameController,
                  decoration: const InputDecoration(
                    labelText: 'Şube İsmi',
                    hintText: 'Örn: Merkez',
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: TextFormField(
                  controller: draft.cityController,
                  decoration: const InputDecoration(
                    labelText: 'Şube Şehir',
                    hintText: 'Örn: İstanbul',
                  ),
                ),
              ),
            ],
          ),
          const Gap(12),
          TextFormField(
            controller: draft.addressController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Adres',
              hintText: 'Cadde, sokak, no, ilçe...',
            ),
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Şube Telefon',
                    hintText: '0 2xx xxx xx xx',
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: TextFormField(
                  controller: draft.latController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Konum Lat',
                    hintText: '41.0',
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: TextFormField(
                  controller: draft.lngController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Konum Lng',
                    hintText: '29.0',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


Future<void> _showExcelImportDialog(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _ExcelImportDialog(),
  );

  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);
}

class _ExcelImportDialog extends ConsumerStatefulWidget {
  const _ExcelImportDialog();

  @override
  ConsumerState<_ExcelImportDialog> createState() => _ExcelImportDialogState();
}

class _ExcelImportDialogState extends ConsumerState<_ExcelImportDialog> {
  List<_ImportCustomer> _customers = [];
  bool _loading = false;
  bool _importing = false;
  String? _error;
  int _importedCount = 0;
  int _failedCount = 0;

  Future<void> _pickFile() async {
    setState(() {
      _loading = true;
      _error = null;
      _customers = [];
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      final bytes = result.files.first.bytes;
      if (bytes == null) {
        setState(() {
          _loading = false;
          _error = 'Dosya okunamadı.';
        });
        return;
      }

      final excel = Excel.decodeBytes(bytes);
      final sheet = excel.tables.values.first;
      if (sheet.rows.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Excel dosyası boş.';
        });
        return;
      }

      // First row is header
      final headers = sheet.rows.first
          .map((c) => c?.value?.toString().toLowerCase().trim() ?? '')
          .toList();

      // Find column indices
      final nameIdx = _findColumnIndex(headers, ['firma', 'firma adı', 'müşteri', 'ad', 'name']);
      final cityIdx = _findColumnIndex(headers, ['şehir', 'il', 'city']);
      final emailIdx = _findColumnIndex(headers, ['email', 'e-posta', 'eposta', 'mail']);
      final vknIdx = _findColumnIndex(headers, ['vkn', 'vergi no', 'vergi kimlik']);
      final phone1Idx = _findColumnIndex(headers, ['telefon', 'tel', 'phone', 'telefon 1', 'tel1']);
      final phone2Idx = _findColumnIndex(headers, ['telefon 2', 'tel2', 'phone2']);
      final notesIdx = _findColumnIndex(headers, ['not', 'notlar', 'notes', 'açıklama']);

      if (nameIdx == -1) {
        setState(() {
          _loading = false;
          _error = 'Firma adı sütunu bulunamadı. İlk satırda "Firma" veya "Firma Adı" başlığı olmalı.';
        });
        return;
      }

      final customers = <_ImportCustomer>[];
      for (var i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final name = _getCellValue(row, nameIdx);
        if (name.isEmpty) continue;

        customers.add(_ImportCustomer(
          name: name,
          city: _getCellValue(row, cityIdx),
          email: _getCellValue(row, emailIdx),
          vkn: _getCellValue(row, vknIdx),
          phone1: _getCellValue(row, phone1Idx),
          phone2: _getCellValue(row, phone2Idx),
          notes: _getCellValue(row, notesIdx),
        ));
      }

      setState(() {
        _loading = false;
        _customers = customers;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Dosya işlenirken hata oluştu: $e';
      });
    }
  }

  int _findColumnIndex(List<String> headers, List<String> possibleNames) {
    for (final name in possibleNames) {
      final idx = headers.indexOf(name);
      if (idx != -1) return idx;
    }
    return -1;
  }

  String _getCellValue(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return '';
    return row[index]?.value?.toString().trim() ?? '';
  }

  Future<void> _import() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() {
      _importing = true;
      _importedCount = 0;
      _failedCount = 0;
    });

    final userId = client.auth.currentUser?.id;

    for (final c in _customers) {
      try {
        await client.from('customers').insert({
          'name': c.name,
          'city': c.city.isEmpty ? null : c.city,
          'email': c.email.isEmpty ? null : c.email,
          'vkn': c.vkn.isEmpty ? null : c.vkn,
          'phone_1': c.phone1.isEmpty ? null : c.phone1,
          'phone_2': c.phone2.isEmpty ? null : c.phone2,
          'notes': c.notes.isEmpty ? null : c.notes,
          'is_active': true,
          'created_by': userId,
        });
        setState(() => _importedCount++);
      } catch (_) {
        setState(() => _failedCount++);
      }
    }

    setState(() => _importing = false);

    if (!mounted) return;
    if (_failedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$_importedCount müşteri başarıyla içe aktarıldı.')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
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
                      'Excel ile Toplu Müşteri İçe Aktar',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: _importing ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F9FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBAE6FD)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF0284C7), size: 20),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Excel Formatı',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Gap(4),
                          Text(
                            'İlk satır başlık olmalı. Gerekli sütunlar: Firma (zorunlu), Şehir, Email, VKN, Telefon, Not',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(16),
              if (_customers.isEmpty && !_loading) ...[
                Center(
                  child: Column(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pickFile,
                        icon: const Icon(Icons.upload_file_rounded),
                        label: const Text('Excel Dosyası Seç (.xlsx)'),
                      ),
                      if (_error != null) ...[
                        const Gap(12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFECACA)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                              const Gap(8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFDC2626)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (_customers.isNotEmpty) ...[
                Row(
                  children: [
                    Text(
                      '${_customers.length} müşteri bulundu',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    if (_importing) ...[
                      Text(
                        'İçe aktarılıyor: $_importedCount / ${_customers.length}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.primary),
                      ),
                      const Gap(8),
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ],
                    if (_failedCount > 0)
                      AppBadge(label: '$_failedCount Hata', tone: AppBadgeTone.error),
                  ],
                ),
                const Gap(12),
                Flexible(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 40,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: Row(
                            children: [
                              Expanded(flex: 3, child: Text('Firma', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                              Expanded(flex: 2, child: Text('Şehir', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                              Expanded(flex: 2, child: Text('Telefon', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: _customers.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final c = _customers[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  children: [
                                    Expanded(flex: 3, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 2, child: Text(c.city.isEmpty ? '—' : c.city, style: Theme.of(context).textTheme.bodySmall)),
                                    Expanded(flex: 2, child: Text(c.phone1.isEmpty ? '—' : c.phone1, style: Theme.of(context).textTheme.bodySmall)),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Gap(16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _importing
                            ? null
                            : () {
                                setState(() {
                                  _customers = [];
                                  _error = null;
                                });
                              },
                        child: const Text('Dosya Değiştir'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _importing ? null : _import,
                        child: _importing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('İçe Aktar'),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImportCustomer {
  final String name;
  final String city;
  final String email;
  final String vkn;
  final String phone1;
  final String phone2;
  final String notes;

  const _ImportCustomer({
    required this.name,
    required this.city,
    required this.email,
    required this.vkn,
    required this.phone1,
    required this.phone2,
    required this.notes,
  });
}
