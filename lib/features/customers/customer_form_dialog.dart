import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/api/api_client.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_section_card.dart';
import '../definitions/definitions_screen.dart';
import 'customer_model.dart';
import 'customers_providers.dart';

class CustomerFormData {
  const CustomerFormData({
    this.id,
    required this.name,
    this.city,
    this.address,
    this.directorName,
    this.email,
    this.vkn,
    this.tcknMs,
    this.phone1Title,
    this.phone1,
    this.phone2Title,
    this.phone2,
    this.phone3Title,
    this.phone3,
    this.notes,
    required this.isActive,
    this.locations = const [],
  });

  final String? id;
  final String name;
  final String? city;
  final String? address;
  final String? directorName;
  final String? email;
  final String? vkn;
  final String? tcknMs;
  final String? phone1Title;
  final String? phone1;
  final String? phone2Title;
  final String? phone2;
  final String? phone3Title;
  final String? phone3;
  final String? notes;
  final bool isActive;
  final List<CustomerLocation> locations;
}

Future<String?> showCreateCustomerDialog(BuildContext context) async {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _CustomerFormDialog(),
  );
}

Future<bool> showEditCustomerDialog(
  BuildContext context, {
  required CustomerFormData initialData,
}) async {
  final result = await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CustomerFormDialog(initialData: initialData),
  );
  return result != null;
}

class _CustomerFormDialog extends ConsumerStatefulWidget {
  const _CustomerFormDialog({this.initialData});

  final CustomerFormData? initialData;

  bool get isEdit => initialData != null;

  @override
  ConsumerState<_CustomerFormDialog> createState() =>
      _CustomerFormDialogState();
}

class _CustomerFormDialogState extends ConsumerState<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _addressController;
  late final TextEditingController _directorNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _vknController;
  late final TextEditingController _tcknMsController;
  late final TextEditingController _phone1TitleController;
  late final TextEditingController _phone1Controller;
  late final TextEditingController _phone2TitleController;
  late final TextEditingController _phone2Controller;
  late final TextEditingController _phone3TitleController;
  late final TextEditingController _phone3Controller;
  late final TextEditingController _notesController;
  late bool _isActive;
  List<_CustomerLocationDraft> _locationDrafts = [];
  bool _saving = false;
  bool _loadingLocations = false;
  final _vknFocusNode = FocusNode();
  final _tcknMsFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final initial = widget.initialData;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _cityController = TextEditingController(text: initial?.city ?? '');
    _addressController = TextEditingController(text: initial?.address ?? '');
    _directorNameController = TextEditingController(
      text: initial?.directorName ?? '',
    );
    _emailController = TextEditingController(text: initial?.email ?? '');
    _vknController = TextEditingController(text: initial?.vkn ?? '');
    _tcknMsController = TextEditingController(text: initial?.tcknMs ?? '');
    _phone1TitleController = TextEditingController(
      text: initial?.phone1Title ?? 'Yetkili',
    );
    _phone1Controller = TextEditingController(text: initial?.phone1 ?? '');
    _phone2TitleController = TextEditingController(
      text: initial?.phone2Title ?? 'Muhasebe',
    );
    _phone2Controller = TextEditingController(text: initial?.phone2 ?? '');
    _phone3TitleController = TextEditingController(
      text: initial?.phone3Title ?? '',
    );
    _phone3Controller = TextEditingController(text: initial?.phone3 ?? '');
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _isActive = initial?.isActive ?? true;
    _locationDrafts = (initial?.locations ?? const [])
        .map(_CustomerLocationDraft.fromLocation)
        .toList(growable: true);
    if (_locationDrafts.isEmpty) {
      _locationDrafts = [_CustomerLocationDraft()];
    }
    if (widget.isEdit && (initial?.id?.isNotEmpty ?? false)) {
      _loadLocations();
    }

    _vknFocusNode.addListener(() {
      if (!_vknFocusNode.hasFocus) {
        _padDigitsController(_vknController, length: 10);
      }
    });
    _tcknMsFocusNode.addListener(() {
      if (!_tcknMsFocusNode.hasFocus) {
        _padDigitsController(_tcknMsController, length: 11);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _directorNameController.dispose();
    _emailController.dispose();
    _vknController.dispose();
    _tcknMsController.dispose();
    _vknFocusNode.dispose();
    _tcknMsFocusNode.dispose();
    _phone1TitleController.dispose();
    _phone1Controller.dispose();
    _phone2TitleController.dispose();
    _phone2Controller.dispose();
    _phone3TitleController.dispose();
    _phone3Controller.dispose();
    _notesController.dispose();
    for (final draft in _locationDrafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _padDigitsController(TextEditingController controller, {required int length}) {
    final digits = controller.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    if (digits.length >= length) return;
    final padded = digits.padLeft(length, '0');
    controller.value = TextEditingValue(
      text: padded,
      selection: TextSelection.collapsed(offset: padded.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _loadLocations() async {
    final customerId = widget.initialData?.id;
    if (customerId == null || customerId.isEmpty) return;
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _loadingLocations = true);
    try {
      final List<Map<String, dynamic>> rows;
      if (apiClient != null) {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {
            'resource': 'customer_locations',
            'customerId': customerId,
          },
        );
        rows = ((response['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      } else {
        final result = await client!
            .from('customer_locations')
            .select(
              'id,customer_id,title,description,address,location_link,location_lat,location_lng,is_active,created_at',
            )
            .eq('customer_id', customerId)
            .eq('is_active', true)
            .order('created_at', ascending: false);
        rows = (result as List).cast<Map<String, dynamic>>();
      }

      final nextDrafts = rows
          .map(
            (row) => _CustomerLocationDraft.fromLocation(
              CustomerLocation.fromJson(row),
            ),
          )
          .toList(growable: true);
      if (!mounted) return;
      setState(() {
        for (final draft in _locationDrafts) {
          draft.dispose();
        }
        _locationDrafts = nextDrafts.isEmpty
            ? [_CustomerLocationDraft()]
            : nextDrafts;
      });
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _loadingLocations = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final citiesAsync = ref.watch(cityDefinitionsProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 1160;
    final isMedium = width >= 860;

    Widget buildCityField() {
      return citiesAsync.when(
        data: (cities) => DropdownButtonFormField<String?>(
          initialValue: _cityController.text.trim().isEmpty
              ? null
              : _cityController.text.trim(),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Şehir seç'),
            ),
            ...cities
                .where((city) => city.isActive)
                .map(
                  (city) => DropdownMenuItem<String?>(
                    value: city.name,
                    child: Text(city.name),
                  ),
                ),
          ],
          onChanged: (value) =>
              setState(() => _cityController.text = value ?? ''),
          decoration: const InputDecoration(
            labelText: 'Şehir',
            prefixIcon: Icon(Icons.location_city_rounded),
          ),
        ),
        loading: () => TextFormField(
          controller: _cityController,
          enabled: false,
          decoration: const InputDecoration(
            labelText: 'Şehir',
            hintText: 'Şehirler yükleniyor',
            prefixIcon: Icon(Icons.location_city_rounded),
          ),
        ),
        error: (error, stackTrace) => TextFormField(
          controller: _cityController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Şehir',
            hintText: 'Şehir bulunamadı',
            prefixIcon: Icon(Icons.location_city_rounded),
          ),
        ),
      );
    }

    String? validateRequiredDigits(
      String? value, {
      required int length,
      required String fieldLabel,
    }) {
      final digits = value?.replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      if (digits.isEmpty) {
        return '$fieldLabel zorunlu';
      }
      if (digits.length != length) {
        return '$fieldLabel tam olarak $length hane olmalı';
      }
      return null;
    }

    Widget buildVknField() {
      return TextFormField(
        controller: _vknController,
        focusNode: _vknFocusNode,
        textInputAction: TextInputAction.next,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(10),
        ],
        decoration: const InputDecoration(
          labelText: 'VKN',
          hintText: '10 haneli vergi numarası',
          prefixIcon: Icon(Icons.badge_outlined),
          counterText: '',
        ),
        onFieldSubmitted: (_) => _padDigitsController(_vknController, length: 10),
        validator: (value) => validateRequiredDigits(
          value,
          length: 10,
          fieldLabel: 'VKN',
        ),
      );
    }

    Widget buildTcknMsField() {
      return TextFormField(
        controller: _tcknMsController,
        focusNode: _tcknMsFocusNode,
        textInputAction: TextInputAction.next,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
        ],
        decoration: const InputDecoration(
          labelText: 'TCKN-MŞ',
          hintText: '11 haneli müşteri sicil / TCKN',
          prefixIcon: Icon(Icons.perm_identity_rounded),
          counterText: '',
        ),
        onFieldSubmitted: (_) =>
            _padDigitsController(_tcknMsController, length: 11),
        validator: (value) => validateRequiredDigits(
          value,
          length: 11,
          fieldLabel: 'TCKN-MŞ',
        ),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1060),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isEdit
                                  ? 'Müşteriyi Düzenle'
                                  : 'Yeni Müşteri',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Gap(6),
                            Text(
                              widget.isEdit
                                  ? 'Firma bilgilerini güncelleyin.'
                                  : 'Firma, iletişim ve temel cari bilgilerini girin.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Gap(18),
                  if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              AppSectionCard(
                                title: 'Temel Bilgiler',
                                subtitle:
                                    'Firma, şehir ve ana adres bilgilerini yönetin.',
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: TextFormField(
                                            controller: _nameController,
                                            textInputAction:
                                                TextInputAction.next,
                                            decoration: const InputDecoration(
                                              labelText: 'Firma Adı',
                                              hintText:
                                                  'Örn. Microvise Teknoloji',
                                              prefixIcon: Icon(
                                                Icons.business_rounded,
                                              ),
                                            ),
                                            validator: (value) {
                                              if (value == null ||
                                                  value.trim().isEmpty) {
                                                return 'Firma adı zorunlu';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                        const Gap(12),
                                        Expanded(
                                          flex: 2,
                                          child: buildCityField(),
                                        ),
                                      ],
                                    ),
                                    const Gap(12),
                                    TextFormField(
                                      controller: _addressController,
                                      textInputAction: TextInputAction.next,
                                      minLines: 2,
                                      maxLines: 3,
                                      decoration: const InputDecoration(
                                        labelText: 'Adres',
                                        hintText: 'Müşterinin ana adresi',
                                        alignLabelWithHint: true,
                                        prefixIcon: Icon(
                                          Icons.location_on_outlined,
                                        ),
                                      ),
                                    ),
                                    const Gap(12),
                                    TextFormField(
                                      controller: _directorNameController,
                                      textInputAction: TextInputAction.next,
                                      decoration: const InputDecoration(
                                        labelText: 'Direktör Ad Soyad',
                                        hintText: 'Örn. Ahmet Yılmaz',
                                        prefixIcon: Icon(
                                          Icons.person_pin_rounded,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Gap(12),
                              AppSectionCard(
                                title: 'Telefonlar',
                                subtitle:
                                    'Yetkili, muhasebe ve opsiyonel telefon alanları.',
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  children: [
                                    _phoneRow(
                                      titleController: _phone1TitleController,
                                      phoneController: _phone1Controller,
                                      titleLabel: 'Telefon 1 Başlığı',
                                      phoneLabel: 'Telefon 1',
                                      phoneHint: '0 5xx xxx xx xx',
                                      phoneIcon: Icons.phone_outlined,
                                    ),
                                    const Gap(12),
                                    _phoneRow(
                                      titleController: _phone2TitleController,
                                      phoneController: _phone2Controller,
                                      titleLabel: 'Telefon 2 Başlığı',
                                      phoneLabel: 'Telefon 2',
                                      phoneHint: '0 2xx xxx xx xx',
                                      phoneIcon: Icons.phone_in_talk_outlined,
                                    ),
                                    const Gap(12),
                                    _phoneRow(
                                      titleController: _phone3TitleController,
                                      phoneController: _phone3Controller,
                                      titleLabel: 'Telefon 3 Başlığı',
                                      phoneLabel: 'Telefon 3',
                                      phoneHint: 'Opsiyonel',
                                      phoneIcon: Icons.phone_callback_outlined,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            children: [
                              AppSectionCard(
                                title: 'Vergi ve Erişim',
                                subtitle:
                                    'Cari kimlik bilgileri ve mail doğrulaması.',
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  children: [
                                    TextFormField(
                                      controller: _emailController,
                                      textInputAction: TextInputAction.next,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(
                                        labelText: 'E-posta',
                                        hintText: 'ornek@firma.com',
                                        prefixIcon: Icon(
                                          Icons.alternate_email_rounded,
                                        ),
                                      ),
                                      validator: (value) {
                                        final email = value?.trim() ?? '';
                                        if (email.isEmpty) return null;
                                        final ok = RegExp(
                                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                                        ).hasMatch(email);
                                        return ok
                                            ? null
                                            : 'Geçerli bir e-posta girin';
                                      },
                                    ),
                                    const Gap(12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: buildVknField(),
                                        ),
                                        const Gap(12),
                                        Expanded(
                                          child: buildTcknMsField(),
                                        ),
                                      ],
                                    ),
                                    const Gap(12),
                                    SwitchListTile.adaptive(
                                      value: _isActive,
                                      contentPadding: EdgeInsets.zero,
                                      onChanged: _saving
                                          ? null
                                          : (value) => setState(
                                              () => _isActive = value,
                                            ),
                                      title: const Text('Aktif Müşteri'),
                                      subtitle: Text(
                                        widget.isEdit
                                            ? 'Pasif kayıtlar listede korunur.'
                                            : 'Pasif kayıtlar listede ayrı görünür.',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Gap(12),
                              AppSectionCard(
                                title: 'İç Notlar',
                                subtitle:
                                    'Süreçte görünmesini istediğiniz dahili notlar.',
                                padding: const EdgeInsets.all(14),
                                child: TextFormField(
                                  controller: _notesController,
                                  minLines: 5,
                                  maxLines: 7,
                                  decoration: const InputDecoration(
                                    labelText: 'Notlar',
                                    hintText: 'Müşteri ile ilgili kısa notlar',
                                    alignLabelWithHint: true,
                                    prefixIcon: Icon(Icons.notes_rounded),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    AppSectionCard(
                      title: 'Temel Bilgiler',
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          if (isMedium)
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _nameController,
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                      labelText: 'Firma Adı',
                                      hintText: 'Örn. Microvise Teknoloji',
                                      prefixIcon: Icon(Icons.business_rounded),
                                    ),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'Firma adı zorunlu';
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                const Gap(12),
                                Expanded(flex: 2, child: buildCityField()),
                              ],
                            )
                          else ...[
                            TextFormField(
                              controller: _nameController,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Firma Adı',
                                hintText: 'Örn. Microvise Teknoloji',
                                prefixIcon: Icon(Icons.business_rounded),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Firma adı zorunlu';
                                }
                                return null;
                              },
                            ),
                            const Gap(12),
                            buildCityField(),
                          ],
                          const Gap(12),
                          TextFormField(
                            controller: _addressController,
                            textInputAction: TextInputAction.next,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Adres',
                              hintText: 'Müşterinin ana adresi',
                              alignLabelWithHint: true,
                              prefixIcon: Icon(Icons.location_on_outlined),
                            ),
                          ),
                          const Gap(12),
                          TextFormField(
                            controller: _directorNameController,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Direktör Ad Soyad',
                              hintText: 'Örn. Ahmet Yılmaz',
                              prefixIcon: Icon(Icons.person_pin_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Gap(12),
                    AppSectionCard(
                      title: 'Vergi ve İletişim',
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'E-posta',
                              hintText: 'ornek@firma.com',
                              prefixIcon: Icon(Icons.alternate_email_rounded),
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty) return null;
                              final ok = RegExp(
                                r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                              ).hasMatch(email);
                              return ok ? null : 'Geçerli bir e-posta girin';
                            },
                          ),
                          const Gap(12),
                          Row(
                            children: [
                              Expanded(
                                child: buildVknField(),
                              ),
                              const Gap(12),
                              Expanded(
                                child: buildTcknMsField(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Gap(12),
                    AppSectionCard(
                      title: 'Telefonlar',
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _phoneRow(
                            titleController: _phone1TitleController,
                            phoneController: _phone1Controller,
                            titleLabel: 'Telefon 1 Başlığı',
                            phoneLabel: 'Telefon 1',
                            phoneHint: '0 5xx xxx xx xx',
                            phoneIcon: Icons.phone_outlined,
                          ),
                          const Gap(12),
                          _phoneRow(
                            titleController: _phone2TitleController,
                            phoneController: _phone2Controller,
                            titleLabel: 'Telefon 2 Başlığı',
                            phoneLabel: 'Telefon 2',
                            phoneHint: '0 2xx xxx xx xx',
                            phoneIcon: Icons.phone_in_talk_outlined,
                          ),
                          const Gap(12),
                          _phoneRow(
                            titleController: _phone3TitleController,
                            phoneController: _phone3Controller,
                            titleLabel: 'Telefon 3 Başlığı',
                            phoneLabel: 'Telefon 3',
                            phoneHint: 'Opsiyonel',
                            phoneIcon: Icons.phone_callback_outlined,
                          ),
                          const Gap(12),
                          SwitchListTile.adaptive(
                            value: _isActive,
                            contentPadding: EdgeInsets.zero,
                            onChanged: _saving
                                ? null
                                : (value) => setState(() => _isActive = value),
                            title: const Text('Aktif Müşteri'),
                            subtitle: Text(
                              widget.isEdit
                                  ? 'Pasif kayıtlar listede korunur.'
                                  : 'Pasif kayıtlar listede ayrı görünür.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Gap(12),
                    AppSectionCard(
                      title: 'İç Notlar',
                      padding: const EdgeInsets.all(12),
                      child: TextFormField(
                        controller: _notesController,
                        minLines: 3,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          labelText: 'Notlar',
                          hintText: 'Müşteri ile ilgili kısa notlar',
                          alignLabelWithHint: true,
                          prefixIcon: Icon(Icons.notes_rounded),
                        ),
                      ),
                    ),
                  ],
                  const Gap(14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Konumlar',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _locationDrafts.add(
                                  _CustomerLocationDraft(),
                                ),
                              ),
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: const Text('Konum Ekle'),
                      ),
                    ],
                  ),
                  const Gap(8),
                  if (_loadingLocations)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  ..._locationDrafts.asMap().entries.map((entry) {
                    final index = entry.key;
                    final draft = entry.value;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom: index == _locationDrafts.length - 1 ? 0 : 12,
                      ),
                      child: _CustomerLocationCard(
                        draft: draft,
                        canRemove: _locationDrafts.length > 1,
                        onRemove: _saving
                            ? null
                            : () => setState(() {
                                draft.dispose();
                                _locationDrafts.removeAt(index);
                                if (_locationDrafts.isEmpty) {
                                  _locationDrafts = [_CustomerLocationDraft()];
                                }
                              }),
                      ),
                    );
                  }),
                  const Gap(18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_saving || _loadingLocations)
                              ? null
                              : _submit,
                          icon: _saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  widget.isEdit
                                      ? Icons.save_rounded
                                      : Icons.add_rounded,
                                  size: 18,
                                ),
                          label: Text(
                            _saving
                                ? (widget.isEdit
                                      ? 'Güncelleniyor...'
                                      : 'Kaydediliyor...')
                                : (widget.isEdit
                                      ? 'Güncelle'
                                      : 'Müşteriyi Kaydet'),
                          ),
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
  }

  Widget _phoneRow({
    required TextEditingController titleController,
    required TextEditingController phoneController,
    required String titleLabel,
    required String phoneLabel,
    required String phoneHint,
    required IconData phoneIcon,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: titleController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: titleLabel,
              prefixIcon: const Icon(Icons.label_outline_rounded),
            ),
          ),
        ),
        const Gap(12),
        Expanded(
          child: TextFormField(
            controller: phoneController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: phoneLabel,
              hintText: phoneHint,
              prefixIcon: Icon(phoneIcon),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    _padDigitsController(_vknController, length: 10);
    _padDigitsController(_tcknMsController, length: 11);
    if (!_formKey.currentState!.validate()) return;

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    if (!widget.isEdit && _phone1Controller.text.trim().isEmpty) {
      _phone1Controller.text = '05333333333';
    }

    final normalizedVkn = _normalizeDigitsFixedLength(_vknController.text, length: 10);
    final normalizedTcknMs =
        _normalizeDigitsFixedLength(_tcknMsController.text, length: 11);
    _vknController.text = normalizedVkn ?? '';
    _tcknMsController.text = normalizedTcknMs ?? '';

    final messenger = ScaffoldMessenger.of(context);

    if (apiClient == null &&
        client != null &&
        normalizedVkn != null &&
        normalizedVkn.trim().isNotEmpty) {
      try {
        var q = client
            .from('customers')
            .select('id,name')
            .eq('vkn', normalizedVkn);
        if (widget.isEdit) {
          q = q.neq('id', widget.initialData!.id!);
        }
        final row = await q.limit(1).maybeSingle();
        final existingId = row?['id']?.toString().trim();
        if ((existingId ?? '').isNotEmpty) {
          final existingName = (row?['name'] ?? '').toString().trim();
          final message = existingName.isEmpty
              ? 'Bu VKN ile kayıtlı müşteri var.'
              : 'Bu VKN ile kayıtlı müşteri var: $existingName';
          if (!mounted) return;
          messenger.showSnackBar(SnackBar(content: Text(message)));
          return;
        }
      } catch (_) {}
    }

    setState(() => _saving = true);
    final payload = {
      'name': _nameController.text.trim(),
      'city': _nullIfEmpty(_cityController.text),
      'address': _nullIfEmpty(_addressController.text),
      'director_name': _nullIfEmpty(_directorNameController.text),
      'email': _nullIfEmpty(_emailController.text),
      'vkn': normalizedVkn,
      'tckn_ms': normalizedTcknMs,
      'phone_1_title': _nullIfEmpty(_phone1TitleController.text),
      'phone_1': _nullIfEmpty(_phone1Controller.text),
      'phone_2_title': _nullIfEmpty(_phone2TitleController.text),
      'phone_2': _nullIfEmpty(_phone2Controller.text),
      'phone_3_title': _nullIfEmpty(_phone3TitleController.text),
      'phone_3': _nullIfEmpty(_phone3Controller.text),
      'notes': _nullIfEmpty(_notesController.text),
      'is_active': _isActive,
    };

    try {
      final locationPayloads = _locationDrafts
          .map((draft) {
            final title = _nullIfEmpty(draft.titleController.text);
            final description = _nullIfEmpty(draft.descriptionController.text);
            final address = _nullIfEmpty(draft.addressController.text);
            return {
              'id': draft.id,
              'title': title ?? address ?? description ?? 'Konum',
              'description': description,
              'address': address,
              'location_link': _nullIfEmpty(draft.locationLinkController.text),
              'location_lat': double.tryParse(draft.latController.text.trim()),
              'location_lng': double.tryParse(draft.lngController.text.trim()),
              'is_active': true,
            };
          })
          .where(
            (row) =>
                (row['title'] as String?) != null ||
                (row['description'] as String?) != null ||
                (row['address'] as String?) != null ||
                (row['location_link'] as String?) != null ||
                row['location_lat'] != null ||
                row['location_lng'] != null,
          )
          .toList(growable: false);

      if (apiClient != null) {
        if (widget.isEdit) {
          await apiClient.patchJson(
            '/customers',
            body: {
              'id': widget.initialData!.id!,
              ...payload,
              'locations': locationPayloads,
            },
          );
          ref.invalidate(customerLocationsProvider(widget.initialData!.id!));
          if (!mounted) return;
          ref.invalidate(customersProvider);
          messenger.showSnackBar(
            const SnackBar(content: Text('Müşteri güncellendi.')),
          );
          Navigator.of(context).pop(widget.initialData!.id);
          return;
        }

        final response = await apiClient.postJson(
          '/customers',
          body: {...payload, 'locations': locationPayloads},
        );
        final customerId = (response['id'] ?? '').toString();
        if (customerId.isEmpty) {
          throw Exception('Müşteri kaydedilemedi.');
        }

        if (!mounted) return;
        ref.invalidate(customersProvider);
        ref.invalidate(customerLocationsProvider(customerId));
        messenger.showSnackBar(
          const SnackBar(content: Text('Müşteri kaydı oluşturuldu.')),
        );
        Navigator.of(context).pop(customerId);
        return;
      }

      final supabase = client!;

      if (widget.isEdit) {
        await supabase
            .from('customers')
            .update(payload)
            .eq('id', widget.initialData!.id!);
        await _saveCustomerLocations(
          supabase,
          customerId: widget.initialData!.id!,
          locationPayloads: locationPayloads,
        );
        ref.invalidate(customerLocationsProvider(widget.initialData!.id!));
        if (!mounted) return;
        ref.invalidate(customersProvider);
        messenger.showSnackBar(
          const SnackBar(content: Text('Müşteri güncellendi.')),
        );
        Navigator.of(context).pop(widget.initialData!.id);
        return;
      }

      final inserted = await supabase
          .from('customers')
          .insert({...payload, 'created_by': supabase.auth.currentUser?.id})
          .select('id')
          .single();

      final customerId = inserted['id'].toString();
      await _saveCustomerLocations(
        supabase,
        customerId: customerId,
        locationPayloads: locationPayloads,
      );

      if (!mounted) return;
      ref.invalidate(customersProvider);
      ref.invalidate(customerLocationsProvider(customerId));
      messenger.showSnackBar(
        const SnackBar(content: Text('Müşteri kaydı oluşturuldu.')),
      );
      Navigator.of(context).pop(customerId);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.isEdit
                ? 'Güncelleme başarısız: $e'
                : 'Müşteri kaydedilemedi: $e',
          ),
        ),
      );
      setState(() => _saving = false);
    }
  }

  String? _nullIfEmpty(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _normalizeDigitsFixedLength(String value, {required int length}) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    if (digits.length == length) return digits;
    if (digits.length > length) return digits.substring(0, length);
    return digits.padLeft(length, '0');
  }

  Future<void> _saveCustomerLocations(
    dynamic client, {
    required String customerId,
    required List<Map<String, dynamic>> locationPayloads,
  }) async {
    await client
        .from('customer_locations')
        .delete()
        .eq('customer_id', customerId);
    if (locationPayloads.isEmpty) {
      return;
    }

    List<Map<String, dynamic>> rows({required bool includeLocationLink}) {
      return [
        for (final row in locationPayloads)
          {
            if ((row['id'] as String?) != null) 'id': row['id'],
            'customer_id': customerId,
            'title': row['title'],
            'description': row['description'],
            'address': row['address'],
            if (includeLocationLink) 'location_link': row['location_link'],
            'location_lat': row['location_lat'],
            'location_lng': row['location_lng'],
            'is_active': true,
            'created_by': client.auth.currentUser?.id,
          },
      ];
    }

    try {
      await client
          .from('customer_locations')
          .insert(rows(includeLocationLink: true));
    } catch (e) {
      final message = e.toString();
      if (!message.contains("'location_link' column")) {
        rethrow;
      }
      await client
          .from('customer_locations')
          .insert(rows(includeLocationLink: false));
    }
  }
}

class _CustomerLocationDraft {
  _CustomerLocationDraft({
    this.id,
    String? title,
    String? description,
    String? address,
    String? locationLink,
    String? lat,
    String? lng,
  }) : titleController = TextEditingController(text: title ?? ''),
       descriptionController = TextEditingController(text: description ?? ''),
       addressController = TextEditingController(text: address ?? ''),
       locationLinkController = TextEditingController(text: locationLink ?? ''),
       latController = TextEditingController(text: lat ?? ''),
       lngController = TextEditingController(text: lng ?? '');

  factory _CustomerLocationDraft.fromLocation(CustomerLocation location) {
    return _CustomerLocationDraft(
      id: location.id,
      title: location.title,
      description: location.description,
      address: location.address,
      locationLink: location.locationLink,
      lat: location.locationLat?.toString(),
      lng: location.locationLng?.toString(),
    );
  }

  final String? id;
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  final TextEditingController addressController;
  final TextEditingController locationLinkController;
  final TextEditingController latController;
  final TextEditingController lngController;

  void dispose() {
    titleController.dispose();
    descriptionController.dispose();
    addressController.dispose();
    locationLinkController.dispose();
    latController.dispose();
    lngController.dispose();
  }
}

class _CustomerLocationCard extends StatelessWidget {
  const _CustomerLocationCard({
    required this.draft,
    required this.canRemove,
    required this.onRemove,
  });

  final _CustomerLocationDraft draft;
  final bool canRemove;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.titleController,
                  decoration: const InputDecoration(
                    labelText: 'Konum Başlığı',
                    hintText: 'Örn. Merkez Ofis',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
              ),
              if (canRemove) ...[
                const Gap(10),
                IconButton(
                  tooltip: 'Konumu sil',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ],
          ),
          const Gap(12),
          TextFormField(
            controller: draft.descriptionController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Konum Açıklaması',
              hintText: 'Servis giriş kapısı, mağaza içi nokta vb.',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.info_outline_rounded),
            ),
          ),
          const Gap(12),
          TextFormField(
            controller: draft.addressController,
            minLines: 2,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Adres',
              hintText: 'Cadde, sokak, no, ilçe...',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.home_work_outlined),
            ),
          ),
          const Gap(12),
          TextFormField(
            controller: draft.locationLinkController,
            decoration: const InputDecoration(
              labelText: 'Konum Linki',
              hintText: 'Google Maps / Apple Maps linki',
              prefixIcon: Icon(Icons.link_rounded),
            ),
          ),
          const Gap(12),
          Row(
            children: [
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
