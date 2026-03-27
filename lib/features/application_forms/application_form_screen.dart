import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../customers/customer_form_dialog.dart';
import '../definitions/definitions_screen.dart';

final applicationFormCustomersProvider = FutureProvider<List<_CustomerOption>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  const pageSize = 500;
  var from = 0;
  final items = <_CustomerOption>[];

  while (true) {
    final rows = await client
        .from('customers')
        .select('id,name,vkn,city,is_active')
        .eq('is_active', true)
        .range(from, from + pageSize - 1);
    final batch = (rows as List)
        .map((row) => _CustomerOption.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
    items.addAll(batch);
    if (batch.length < pageSize) break;
    from += pageSize;
  }

  items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
  return items;
});

final applicationFormStockProductsProvider =
    FutureProvider<List<_StockProductOption>>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return const [];

      final rows = await client
          .from('products')
          .select('id,code,name,is_active')
          .eq('is_active', true)
          .order('name');

      final items = (rows as List)
          .map(
            (row) => _StockProductOption.fromJson(row as Map<String, dynamic>),
          )
          .toList(growable: false);
      items.sort((a, b) => _sortKey(a.label).compareTo(_sortKey(b.label)));
      return items;
    });

final applicationFormsProvider = FutureProvider<List<_ApplicationFormSummary>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('application_forms')
      .select(
        'id,application_date,customer_name,invoice_number,document_type,brand_name,model_name,business_activity_name,created_at',
      )
      .order('created_at', ascending: false)
      .limit(10);

  return (rows as List)
      .map(
        (row) => _ApplicationFormSummary.fromJson(row as Map<String, dynamic>),
      )
      .toList(growable: false);
});

class ApplicationFormScreen extends ConsumerStatefulWidget {
  const ApplicationFormScreen({super.key});

  @override
  ConsumerState<ApplicationFormScreen> createState() =>
      _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends ConsumerState<ApplicationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  late final TextEditingController _customerController;
  late final TextEditingController _workAddressController;
  late final TextEditingController _fileRegistryController;
  late final TextEditingController _directorController;
  late final TextEditingController _accountingOfficeController;
  late final TextEditingController _stockRegistryNumberController;
  late final TextEditingController _invoiceNumberController;
  DateTime _applicationDate = DateTime.now();
  DateTime _okcStartDate = DateTime.now();
  String _documentType = 'VKN';
  String? _selectedCustomerId;
  String? _selectedCityId;
  String? _selectedBrandId;
  String? _selectedModelId;
  String? _selectedFiscalSymbolId;
  String? _selectedStockProductId;
  String? _selectedBusinessActivityId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _customerController = TextEditingController();
    _workAddressController = TextEditingController();
    _fileRegistryController = TextEditingController();
    _directorController = TextEditingController();
    _accountingOfficeController = TextEditingController();
    _stockRegistryNumberController = TextEditingController();
    _invoiceNumberController = TextEditingController();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _workAddressController.dispose();
    _fileRegistryController.dispose();
    _directorController.dispose();
    _accountingOfficeController.dispose();
    _stockRegistryNumberController.dispose();
    _invoiceNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime currentValue,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentValue,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (picked == null) return;
    onSelected(picked);
  }

  Future<void> _createCustomer() async {
    final newCustomerId = await showCreateCustomerDialog(context);
    if (newCustomerId == null) return;
    ref.invalidate(applicationFormCustomersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final customers = await ref.read(applicationFormCustomersProvider.future);
    final created = customers
        .where((item) => item.id == newCustomerId)
        .firstOrNull;
    if (created == null || !mounted) return;
    setState(() {
      _selectedCustomerId = created.id;
      _customerController.text = created.name;
      if (_fileRegistryController.text.trim().isEmpty) {
        _fileRegistryController.text = created.vkn ?? '';
      }
      final city = ref
          .read(cityDefinitionsProvider)
          .asData
          ?.value
          .firstWhere(
            (item) => _sortKey(item.name) == _sortKey(created.city ?? ''),
            orElse: () => CityDefinition(id: '', name: '', code: null),
          );
      if (city != null && city.id.isNotEmpty) {
        _selectedCityId = city.id;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    final customers = ref.read(applicationFormCustomersProvider).asData?.value;
    final cities = ref.read(cityDefinitionsProvider).asData?.value;
    final brands = ref.read(deviceBrandsProvider).asData?.value;
    final models = ref.read(deviceModelsProvider).asData?.value;
    final fiscalSymbols = ref.read(fiscalSymbolsProvider).asData?.value;
    final stockProducts = ref
        .read(applicationFormStockProductsProvider)
        .asData
        ?.value;
    final activities = ref.read(businessActivityTypesProvider).asData?.value;

    final customer = customers
        ?.where((item) => item.id == _selectedCustomerId)
        .firstOrNull;
    final city = cities
        ?.where((item) => item.id == _selectedCityId)
        .firstOrNull;
    final brand = brands
        ?.where((item) => item.id == _selectedBrandId)
        .firstOrNull;
    final model = models
        ?.where((item) => item.id == _selectedModelId)
        .firstOrNull;
    final fiscal = fiscalSymbols
        ?.where((item) => item.id == _selectedFiscalSymbolId)
        .firstOrNull;
    final stockProduct = stockProducts
        ?.where((item) => item.id == _selectedStockProductId)
        .firstOrNull;
    final activity = activities
        ?.where((item) => item.id == _selectedBusinessActivityId)
        .firstOrNull;

    setState(() => _saving = true);
    try {
      await client.from('application_forms').insert({
        'application_date': DateFormat('yyyy-MM-dd').format(_applicationDate),
        'customer_id': customer?.id,
        'customer_name': _customerController.text.trim(),
        'work_address': _workAddressController.text.trim(),
        'tax_office_city_id': city?.id.isEmpty ?? true ? null : city?.id,
        'tax_office_city_name': city?.name,
        'document_type': _documentType,
        'file_registry_number': _fileRegistryController.text.trim().isEmpty
            ? null
            : _fileRegistryController.text.trim(),
        'director': _directorController.text.trim().isEmpty
            ? null
            : _directorController.text.trim(),
        'brand_id': brand?.id,
        'brand_name': brand?.name,
        'model_id': model?.id,
        'model_name': model?.name,
        'fiscal_symbol_id': fiscal?.id,
        'fiscal_symbol_name': fiscal?.code?.trim().isNotEmpty ?? false
            ? fiscal!.code!.trim()
            : fiscal?.name,
        'stock_product_id': stockProduct?.id,
        'stock_product_name': stockProduct?.name,
        'stock_registry_number':
            _stockRegistryNumberController.text.trim().isEmpty
            ? null
            : _stockRegistryNumberController.text.trim(),
        'accounting_office': _accountingOfficeController.text.trim().isEmpty
            ? null
            : _accountingOfficeController.text.trim(),
        'okc_start_date': DateFormat('yyyy-MM-dd').format(_okcStartDate),
        'business_activity_type_id': activity?.id,
        'business_activity_name': activity?.name,
        'invoice_number': _invoiceNumberController.text.trim().isEmpty
            ? null
            : _invoiceNumberController.text.trim(),
      });
      ref.invalidate(applicationFormsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Başvuru formu kaydedildi.')),
      );
      setState(() {
        _applicationDate = DateTime.now();
        _okcStartDate = DateTime.now();
        _documentType = 'VKN';
        _selectedCustomerId = null;
        _selectedCityId = null;
        _selectedBrandId = null;
        _selectedModelId = null;
        _selectedFiscalSymbolId = null;
        _selectedStockProductId = null;
        _selectedBusinessActivityId = null;
        _customerController.clear();
        _workAddressController.clear();
        _fileRegistryController.clear();
        _directorController.clear();
        _accountingOfficeController.clear();
        _stockRegistryNumberController.clear();
        _invoiceNumberController.clear();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 900;
    final customersAsync = ref.watch(applicationFormCustomersProvider);
    final citiesAsync = ref.watch(cityDefinitionsProvider);
    final brandsAsync = ref.watch(deviceBrandsProvider);
    final modelsAsync = ref.watch(deviceModelsProvider);
    final fiscalSymbolsAsync = ref.watch(fiscalSymbolsProvider);
    final stockProductsAsync = ref.watch(applicationFormStockProductsProvider);
    final activitiesAsync = ref.watch(businessActivityTypesProvider);
    final recentFormsAsync = ref.watch(applicationFormsProvider);

    final selectedBrandId = _selectedBrandId;
    final filteredModels =
        modelsAsync.asData?.value
            .where(
              (item) =>
                  item.isActive &&
                  (selectedBrandId == null || item.brandId == selectedBrandId),
            )
            .toList(growable: false) ??
        const <DeviceModel>[];

    return AppPageLayout(
      title: 'Başvuru Formu',
      subtitle: 'Yeni mali başvuru formunu oluşturun ve son kayıtları izleyin.',
      actions: [
        OutlinedButton.icon(
          onPressed: _saving
              ? null
              : () {
                  setState(() {
                    _applicationDate = DateTime.now();
                    _okcStartDate = DateTime.now();
                  });
                },
          icon: const Icon(Icons.today_rounded, size: 18),
          label: const Text('Bugüne Dön'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_rounded, size: 18),
          label: const Text('Kaydet'),
        ),
      ],
      body: Column(
        children: [
          Flex(
            direction: isMobile ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: AppCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Yeni Başvuru',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(6),
                        Text(
                          'Sarı alanlar başlık, kırmızı alanlar form içeriği olacak şekilde düzenlendi.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                        const Gap(18),
                        _FormRow(
                          label: "Satışa Ait Faturanın Tarihi",
                          child: _DateField(
                            value: _applicationDate,
                            format: _dateFormat,
                            onTap: () => _pickDate(
                              currentValue: _applicationDate,
                              onSelected: (value) =>
                                  setState(() => _applicationDate = value),
                            ),
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Adı Soyadı / Ünvanı',
                          child: customersAsync.when(
                            data: (items) => _CustomerAutocompleteField(
                              customers: items,
                              controller: _customerController,
                              selectedCustomerId: _selectedCustomerId,
                              onSelected: (customer) {
                                setState(() {
                                  _selectedCustomerId = customer.id;
                                  _customerController.text = customer.name;
                                  _fileRegistryController.text =
                                      customer.vkn ?? '';
                                  final city = citiesAsync.asData?.value
                                      .where(
                                        (item) =>
                                            _sortKey(item.name) ==
                                            _sortKey(customer.city ?? ''),
                                      )
                                      .firstOrNull;
                                  if (city != null) {
                                    _selectedCityId = city.id;
                                  }
                                });
                              },
                              onChanged: () {
                                setState(() => _selectedCustomerId = null);
                              },
                              onCreateCustomer: _createCustomer,
                            ),
                            loading: () => const _ContentLoading(),
                            error: (error, stackTrace) => const _ContentError(),
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'İş yeri Adresi',
                          child: _ApplicationTextField(
                            controller: _workAddressController,
                            minLines: 2,
                            maxLines: 3,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'İş adresi zorunlu.';
                              }
                              return null;
                            },
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Bağlı Olduğu Vergi Dairesi',
                          child: citiesAsync.when(
                            data: (items) => _ApplicationDropdown<String>(
                              value: _selectedCityId,
                              items: items
                                  .where((item) => item.isActive)
                                  .map(
                                    (item) => DropdownMenuItem<String>(
                                      value: item.id,
                                      child: Text(item.name),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (value) =>
                                  setState(() => _selectedCityId = value),
                              validator: (value) =>
                                  value == null ? 'Vergi dairesi seçin.' : null,
                            ),
                            loading: () => const _ContentLoading(),
                            error: (error, stackTrace) => const _ContentError(),
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Türü',
                          child: _ApplicationDropdown<String>(
                            value: _documentType,
                            items: const [
                              DropdownMenuItem(
                                value: 'VKN',
                                child: Text('VKN'),
                              ),
                            ],
                            onChanged: null,
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Dosya Sicil No',
                          child: _ApplicationTextField(
                            controller: _fileRegistryController,
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Direktör',
                          child: _ApplicationTextField(
                            controller: _directorController,
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Markası ve Modeli',
                          child: Column(
                            children: [
                              brandsAsync.when(
                                data: (items) => _ApplicationDropdown<String>(
                                  value: _selectedBrandId,
                                  hintText: 'Marka seçin',
                                  items: items
                                      .where((item) => item.isActive)
                                      .map(
                                        (item) => DropdownMenuItem<String>(
                                          value: item.id,
                                          child: Text(item.name),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedBrandId = value;
                                      _selectedModelId = null;
                                    });
                                  },
                                  validator: (value) =>
                                      value == null ? 'Marka seçin.' : null,
                                ),
                                loading: () => const _ContentLoading(),
                                error: (error, stackTrace) =>
                                    const _ContentError(),
                              ),
                              const Gap(8),
                              _ApplicationDropdown<String>(
                                value: _selectedModelId,
                                hintText: 'Model seçin',
                                items: filteredModels
                                    .map(
                                      (item) => DropdownMenuItem<String>(
                                        value: item.id,
                                        child: Text(item.name),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (value) =>
                                    setState(() => _selectedModelId = value),
                                validator: (value) =>
                                    value == null ? 'Model seçin.' : null,
                              ),
                            ],
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Mali Sembol ve Firma Kodu',
                          child: fiscalSymbolsAsync.when(
                            data: (items) => _ApplicationDropdown<String>(
                              value: _selectedFiscalSymbolId,
                              items: items
                                  .where((item) => item.isActive)
                                  .map(
                                    (item) => DropdownMenuItem<String>(
                                      value: item.id,
                                      child: Text(
                                        item.code?.trim().isNotEmpty ?? false
                                            ? '${item.code} - ${item.name}'
                                            : item.name,
                                      ),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (value) => setState(
                                () => _selectedFiscalSymbolId = value,
                              ),
                              validator: (value) =>
                                  value == null ? 'Mali sembol seçin.' : null,
                            ),
                            loading: () => const _ContentLoading(),
                            error: (error, stackTrace) => const _ContentError(),
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Sicil Numarası',
                          child: Column(
                            children: [
                              stockProductsAsync.when(
                                data: (items) => _ApplicationDropdown<String>(
                                  value: _selectedStockProductId,
                                  hintText: 'Stok listesinden seçin',
                                  items: items
                                      .map(
                                        (item) => DropdownMenuItem<String>(
                                          value: item.id,
                                          child: Text(item.label),
                                        ),
                                      )
                                      .toList(growable: false),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedStockProductId = value;
                                      final selected = items
                                          .where((item) => item.id == value)
                                          .firstOrNull;
                                      if (selected != null &&
                                          _stockRegistryNumberController.text
                                              .trim()
                                              .isEmpty) {
                                        _stockRegistryNumberController.text =
                                            selected.code?.trim().isNotEmpty ??
                                                false
                                            ? selected.code!.trim()
                                            : selected.name;
                                      }
                                    });
                                  },
                                ),
                                loading: () => const _ContentLoading(),
                                error: (error, stackTrace) =>
                                    const _ContentError(),
                              ),
                              const Gap(8),
                              _ApplicationTextField(
                                controller: _stockRegistryNumberController,
                              ),
                            ],
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Muhasebe Ofisi',
                          child: _ApplicationTextField(
                            controller: _accountingOfficeController,
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'ÖKC Kullanma Tarihi',
                          child: _DateField(
                            value: _okcStartDate,
                            format: _dateFormat,
                            onTap: () => _pickDate(
                              currentValue: _okcStartDate,
                              onSelected: (value) =>
                                  setState(() => _okcStartDate = value),
                            ),
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Ticari Faaliyet / Meslek Türü',
                          child: activitiesAsync.when(
                            data: (items) => _ApplicationDropdown<String>(
                              value: _selectedBusinessActivityId,
                              items: items
                                  .where((item) => item.isActive)
                                  .map(
                                    (item) => DropdownMenuItem<String>(
                                      value: item.id,
                                      child: Text(item.name),
                                    ),
                                  )
                                  .toList(growable: false),
                              onChanged: (value) => setState(
                                () => _selectedBusinessActivityId = value,
                              ),
                              validator: (value) =>
                                  value == null ? 'Meslek türü seçin.' : null,
                            ),
                            loading: () => const _ContentLoading(),
                            error: (error, stackTrace) => const _ContentError(),
                          ),
                        ),
                        const Gap(10),
                        _FormRow(
                          label: 'Fatura No',
                          child: _ApplicationTextField(
                            controller: _invoiceNumberController,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!isMobile) const Gap(16),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Form Özeti',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const Gap(12),
                          _SummaryLine(
                            label: 'Tarih',
                            value: _dateFormat.format(_applicationDate),
                          ),
                          _SummaryLine(
                            label: 'Müşteri',
                            value: _customerController.text.trim().isEmpty
                                ? 'Seçilmedi'
                                : _customerController.text.trim(),
                          ),
                          _SummaryLine(
                            label: 'Dosya Sicil',
                            value: _fileRegistryController.text.trim().isEmpty
                                ? '—'
                                : _fileRegistryController.text.trim(),
                          ),
                          _SummaryLine(
                            label: 'ÖKC Başlangıç',
                            value: _dateFormat.format(_okcStartDate),
                          ),
                        ],
                      ),
                    ),
                    const Gap(16),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Son Başvurular',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                              ),
                              AppBadge(
                                label: 'Canlı',
                                tone: AppBadgeTone.primary,
                              ),
                            ],
                          ),
                          const Gap(12),
                          recentFormsAsync.when(
                            data: (items) {
                              if (items.isEmpty) {
                                return const Text('Henüz kayıt yok.');
                              }
                              return Column(
                                children: [
                                  for (final item in items) ...[
                                    _RecentApplicationTile(item: item),
                                    if (item != items.last) const Gap(10),
                                  ],
                                ],
                              );
                            },
                            loading: () => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            error: (error, stackTrace) =>
                                const Text('Kayıtlar yüklenemedi.'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 900;
    final labelBox = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFDEB48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3C91B)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF3E3200),
        ),
      ),
    );

    final contentBox = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF5F5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF4C7C7)),
      ),
      child: child,
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [labelBox, const Gap(8), contentBox],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 260, child: labelBox),
        const Gap(10),
        Expanded(child: contentBox),
      ],
    );
  }
}

class _ApplicationTextField extends StatelessWidget {
  const _ApplicationTextField({
    required this.controller,
    this.minLines,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final int? minLines;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: const Color(0xFFC1121F),
        fontWeight: FontWeight.w700,
      ),
      decoration: const InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(),
      ),
    );
  }
}

class _ApplicationDropdown<T> extends StatelessWidget {
  const _ApplicationDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.hintText,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: const Color(0xFFC1121F),
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(),
        hintText: hintText,
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.format,
    required this.onTap,
  });

  final DateTime value;
  final DateFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          format.format(value),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFFC1121F),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _CustomerAutocompleteField extends StatelessWidget {
  const _CustomerAutocompleteField({
    required this.customers,
    required this.controller,
    required this.selectedCustomerId,
    required this.onSelected,
    required this.onChanged,
    required this.onCreateCustomer,
  });

  final List<_CustomerOption> customers;
  final TextEditingController controller;
  final String? selectedCustomerId;
  final ValueChanged<_CustomerOption> onSelected;
  final VoidCallback onChanged;
  final VoidCallback onCreateCustomer;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Autocomplete<_CustomerOption>(
          optionsBuilder: (textEditingValue) {
            final query = _sortKey(textEditingValue.text);
            if (query.isEmpty) return customers.take(20);
            return customers
                .where((item) {
                  return _sortKey(item.name).contains(query) ||
                      _sortKey(item.vkn ?? '').contains(query);
                })
                .take(20);
          },
          displayStringForOption: (option) => option.name,
          onSelected: onSelected,
          fieldViewBuilder: (context, textController, focusNode, onSubmit) {
            textController.text = controller.text;
            textController.selection = TextSelection.collapsed(
              offset: textController.text.length,
            );
            return TextFormField(
              controller: textController,
              focusNode: focusNode,
              validator: (_) => (selectedCustomerId ?? '').isEmpty
                  ? 'Müşteri seçin veya ekleyin.'
                  : null,
              onChanged: (_) => onChanged(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: const Color(0xFFC1121F),
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                hintText: 'Firma adı yazın ve seçin',
              ),
            );
          },
        ),
        const Gap(8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: onCreateCustomer,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('Yeni müşteri ekle'),
          ),
        ),
      ],
    );
  }
}

class _ContentLoading extends StatelessWidget {
  const _ContentLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 46,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _ContentError extends StatelessWidget {
  const _ContentError();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 46, child: Text('Veri yüklenemedi.'));
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
            ),
          ),
          const Gap(10),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentApplicationTile extends StatelessWidget {
  const _RecentApplicationTile({required this.item});

  final _ApplicationFormSummary item;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      item.brandModel,
      item.businessActivityName,
      if (item.invoiceNumber?.trim().isNotEmpty ?? false)
        'Fatura: ${item.invoiceNumber}',
    ].whereType<String>().where((text) => text.trim().isNotEmpty).join(' • ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
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
                  item.customerName,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              AppBadge(label: item.documentType, tone: AppBadgeTone.primary),
            ],
          ),
          const Gap(4),
          Text(
            DateFormat('d MMM y', 'tr_TR').format(item.applicationDate),
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
          ),
          if (subtitle.isNotEmpty) ...[
            const Gap(6),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerOption {
  const _CustomerOption({
    required this.id,
    required this.name,
    required this.vkn,
    required this.city,
  });

  final String id;
  final String name;
  final String? vkn;
  final String? city;

  factory _CustomerOption.fromJson(Map<String, dynamic> json) {
    return _CustomerOption(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      vkn: json['vkn']?.toString(),
      city: json['city']?.toString(),
    );
  }
}

class _ApplicationFormSummary {
  const _ApplicationFormSummary({
    required this.id,
    required this.applicationDate,
    required this.customerName,
    required this.documentType,
    required this.brandName,
    required this.modelName,
    required this.businessActivityName,
    required this.invoiceNumber,
  });

  final String id;
  final DateTime applicationDate;
  final String customerName;
  final String documentType;
  final String? brandName;
  final String? modelName;
  final String? businessActivityName;
  final String? invoiceNumber;

  String get brandModel => [
    brandName,
    modelName,
  ].whereType<String>().where((e) => e.isNotEmpty).join(' / ');

  factory _ApplicationFormSummary.fromJson(Map<String, dynamic> json) {
    final parsedDate =
        DateTime.tryParse(json['application_date']?.toString() ?? '') ??
        DateTime.now();
    return _ApplicationFormSummary(
      id: json['id'].toString(),
      applicationDate: parsedDate,
      customerName: json['customer_name']?.toString() ?? '—',
      documentType: json['document_type']?.toString() ?? 'VKN',
      brandName: json['brand_name']?.toString(),
      modelName: json['model_name']?.toString(),
      businessActivityName: json['business_activity_name']?.toString(),
      invoiceNumber: json['invoice_number']?.toString(),
    );
  }
}

class _StockProductOption {
  const _StockProductOption({
    required this.id,
    required this.name,
    required this.code,
  });

  final String id;
  final String name;
  final String? code;

  String get label =>
      code?.trim().isNotEmpty ?? false ? '${code!.trim()} - $name' : name;

  factory _StockProductOption.fromJson(Map<String, dynamic> json) {
    return _StockProductOption(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString(),
    );
  }
}

String _sortKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('i̇', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u');
}
