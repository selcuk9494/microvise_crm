import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_card.dart';

class CustomerFormData {
  const CustomerFormData({
    this.id,
    required this.name,
    this.city,
    this.email,
    this.vkn,
    this.phone1Title,
    this.phone1,
    this.phone2Title,
    this.phone2,
    this.phone3Title,
    this.phone3,
    this.notes,
    required this.isActive,
  });

  final String? id;
  final String name;
  final String? city;
  final String? email;
  final String? vkn;
  final String? phone1Title;
  final String? phone1;
  final String? phone2Title;
  final String? phone2;
  final String? phone3Title;
  final String? phone3;
  final String? notes;
  final bool isActive;
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
  late final TextEditingController _emailController;
  late final TextEditingController _vknController;
  late final TextEditingController _phone1TitleController;
  late final TextEditingController _phone1Controller;
  late final TextEditingController _phone2TitleController;
  late final TextEditingController _phone2Controller;
  late final TextEditingController _phone3TitleController;
  late final TextEditingController _phone3Controller;
  late final TextEditingController _notesController;
  late bool _isActive;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialData;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _cityController = TextEditingController(text: initial?.city ?? '');
    _emailController = TextEditingController(text: initial?.email ?? '');
    _vknController = TextEditingController(text: initial?.vkn ?? '');
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
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _emailController.dispose();
    _vknController.dispose();
    _phone1TitleController.dispose();
    _phone1Controller.dispose();
    _phone2TitleController.dispose();
    _phone2Controller.dispose();
    _phone3TitleController.dispose();
    _phone3Controller.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: AppCard(
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
                  const Gap(20),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
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
                      ),
                      const Gap(12),
                      Expanded(
                        child: TextFormField(
                          controller: _cityController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Şehir',
                            hintText: 'Örn. İstanbul',
                            prefixIcon: Icon(Icons.location_city_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
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
                      ),
                      const Gap(12),
                      Expanded(
                        child: TextFormField(
                          controller: _vknController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'VKN / TCKN',
                            hintText: 'Vergi numarası',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _phone1TitleController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Telefon 1 Başlığı',
                            prefixIcon: Icon(Icons.label_outline_rounded),
                          ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: TextFormField(
                          controller: _phone1Controller,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Telefon 1',
                            hintText: '0 5xx xxx xx xx',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _phone2TitleController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Telefon 2 Başlığı',
                            prefixIcon: Icon(Icons.label_outline_rounded),
                          ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: TextFormField(
                          controller: _phone2Controller,
                          textInputAction: TextInputAction.next,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Telefon 2',
                            hintText: '0 2xx xxx xx xx',
                            prefixIcon: Icon(Icons.phone_in_talk_outlined),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _phone3TitleController,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Telefon 3 Başlığı',
                            prefixIcon: Icon(Icons.label_outline_rounded),
                          ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: TextFormField(
                          controller: _phone3Controller,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Telefon 3',
                            hintText: 'Opsiyonel',
                            prefixIcon: Icon(Icons.phone_callback_outlined),
                          ),
                        ),
                      ),
                    ],
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
                  const Gap(8),
                  TextFormField(
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
                  const Gap(20),
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
                          onPressed: _saving ? null : _submit,
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final payload = {
      'name': _nameController.text.trim(),
      'city': _nullIfEmpty(_cityController.text),
      'email': _nullIfEmpty(_emailController.text),
      'vkn': _nullIfEmpty(_vknController.text),
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
      if (widget.isEdit) {
        await client
            .from('customers')
            .update(payload)
            .eq('id', widget.initialData!.id!);
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Müşteri güncellendi.')),
        );
        Navigator.of(context).pop(widget.initialData!.id);
        return;
      }

      final inserted = await client
          .from('customers')
          .insert({...payload, 'created_by': client.auth.currentUser?.id})
          .select('id')
          .single();

      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Müşteri kaydı oluşturuldu.')),
      );
      Navigator.of(context).pop(inserted['id'].toString());
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
}
