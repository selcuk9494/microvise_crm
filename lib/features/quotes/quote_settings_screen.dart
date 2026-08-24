import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_card.dart';
import 'quote_bank_details.dart';
import 'quote_settings_model.dart';
import 'quote_settings_provider.dart';

class QuoteSettingsScreen extends ConsumerStatefulWidget {
  const QuoteSettingsScreen({super.key});

  @override
  ConsumerState<QuoteSettingsScreen> createState() =>
      _QuoteSettingsScreenState();
}

class _QuoteSettingsScreenState extends ConsumerState<QuoteSettingsScreen> {
  final _companyTitle = TextEditingController();
  final _companySubtitle = TextEditingController();
  final _bankName = TextEditingController();
  final _bankAccountName = TextEditingController();
  final _bankIbanTl = TextEditingController();
  final _bankIbanUsd = TextEditingController();
  final _bankExtra = TextEditingController();
  final _terms = TextEditingController();

  bool _hydrated = false;
  bool _saving = false;
  String? _logoUrl;
  Uint8List? _pendingLogoBytes;
  String? _pendingLogoMime;
  String? _pendingLogoName;
  bool _logoRemoved = false;

  @override
  void dispose() {
    _companyTitle.dispose();
    _companySubtitle.dispose();
    _bankName.dispose();
    _bankAccountName.dispose();
    _bankIbanTl.dispose();
    _bankIbanUsd.dispose();
    _bankExtra.dispose();
    _terms.dispose();
    super.dispose();
  }

  void _hydrate(QuoteDocumentSettings settings) {
    if (_hydrated) return;
    _logoUrl = settings.logoUrl;
    _companyTitle.text = settings.companyTitle;
    _companySubtitle.text = settings.companySubtitle;
    _terms.text = settings.termsAndConditions;
    final parsed = parseQuoteBankDetails(settings.bankDetails);
    _bankName.text = parsed.bankName;
    _bankAccountName.text = parsed.accountName;
    _bankIbanTl.text = formatQuoteIban(parsed.ibanTl);
    _bankIbanUsd.text = formatQuoteIban(parsed.ibanUsd);
    _bankExtra.text = parsed.extraLines;
    _hydrated = true;
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;
    final name = picked.name.toLowerCase();
    final mime = name.endsWith('.png')
        ? 'image/png'
        : name.endsWith('.webp')
        ? 'image/webp'
        : 'image/jpeg';
    setState(() {
      _pendingLogoBytes = bytes;
      _pendingLogoMime = mime;
      _pendingLogoName = picked.name;
      _logoRemoved = false;
    });
  }

  String _composedBankDetails() => composeQuoteBankDetails(
    bankName: _bankName.text,
    accountName: _bankAccountName.text,
    ibanTl: _bankIbanTl.text,
    ibanUsd: _bankIbanUsd.text,
    extraLines: _bankExtra.text,
  );

  Future<void> _save() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      _message('API bağlantısı yok.');
      return;
    }

    setState(() => _saving = true);
    try {
      var logoUrl = _logoUrl;
      if (_logoRemoved) {
        logoUrl = null;
      }

      if (_pendingLogoBytes != null && _pendingLogoMime != null) {
        final uploaded = await apiClient.postJson('/mutate', body: {
          'op': 'uploadQuoteLogo',
          'filename':
              _pendingLogoName ??
              'quote-logo-${DateTime.now().millisecondsSinceEpoch}.jpg',
          'contentType': _pendingLogoMime,
          'data': base64Encode(_pendingLogoBytes!),
        });
        final uploadedUrl = uploaded['url']?.toString().trim();
        if (uploadedUrl != null && uploadedUrl.isNotEmpty) {
          logoUrl = uploadedUrl;
        }
      }

      await apiClient.postJson('/mutate', body: {
        'op': 'upsert',
        'table': 'quote_document_settings',
        'returning': 'row',
        'values': {
          'id': 1,
          'company_title': _companyTitle.text.trim().isEmpty
              ? 'MICROVISE'
              : _companyTitle.text.trim(),
          'company_subtitle': _companySubtitle.text.trim().isEmpty
              ? 'Innovation Ltd'
              : _companySubtitle.text.trim(),
          'bank_details': _composedBankDetails(),
          'terms_and_conditions': _terms.text.trim().isEmpty
              ? null
              : _terms.text.trim(),
          'logo_url': logoUrl,
        },
      });

      ref.invalidate(quoteDocumentSettingsProvider);
      if (!mounted) return;
      setState(() {
        _logoUrl = logoUrl;
        _pendingLogoBytes = null;
        _pendingLogoMime = null;
        _pendingLogoName = null;
        _logoRemoved = false;
      });
      _message('Teklif ayarları kaydedildi.');
    } catch (error) {
      if (mounted) _message('Kaydedilemedi: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(quoteDocumentSettingsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Teklif listesine dön',
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: _saving ? null : () => context.go('/e-fatura/teklif'),
        ),
        title: const Text('Teklif Ayarları'),
        actions: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(LucideIcons.save, size: 18),
            label: const Text('Kaydet'),
          ),
          const Gap(12),
        ],
      ),
      body: settingsAsync.when(
        data: (settings) {
          _hydrate(settings);
          return ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
            children: [
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Logo',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Gap(8),
                    Text(
                      'Teklif PDF üst bölümünde görünür. Önerilen: yatay logo, en fazla 1200 px genişlik.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSoft,
                      ),
                    ),
                    const Gap(14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 160,
                          height: 72,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceMuted,
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusSm,
                            ),
                            border: Border.all(color: AppTheme.border),
                          ),
                          alignment: Alignment.center,
                          child: _pendingLogoBytes != null
                              ? Image.memory(
                                  _pendingLogoBytes!,
                                  fit: BoxFit.contain,
                                )
                              : (_logoUrl != null &&
                                    _logoUrl!.trim().isNotEmpty &&
                                    !_logoRemoved)
                              ? Image.network(
                                  _logoUrl!,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Text(
                                    'Logo yüklenemedi',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                )
                              : Text(
                                  'Logo yok',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.textSoft),
                                ),
                        ),
                        const Gap(12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _saving ? null : _pickLogo,
                              icon: const Icon(LucideIcons.image, size: 18),
                              label: const Text('Logo seç'),
                            ),
                            if ((_logoUrl ?? '').isNotEmpty ||
                                _pendingLogoBytes != null) ...[
                              const Gap(8),
                              TextButton.icon(
                                onPressed: _saving
                                    ? null
                                    : () => setState(() {
                                        _logoRemoved = true;
                                        _pendingLogoBytes = null;
                                        _pendingLogoMime = null;
                                        _pendingLogoName = null;
                                      }),
                                icon: const Icon(LucideIcons.trash2, size: 16),
                                label: const Text('Logoyu kaldır'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                    const Gap(16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _companyTitle,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Üst başlık (logo yoksa)',
                            ),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: TextField(
                            controller: _companySubtitle,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Alt başlık (logo yoksa)',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(14),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Banka Hesap Bilgileri',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Gap(8),
                    Text(
                      'PDF alt bölümündeki yeşil banka kutusunda gösterilir.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSoft,
                      ),
                    ),
                    const Gap(14),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bankName,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Banka',
                            ),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: TextField(
                            controller: _bankAccountName,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Hesap sahibi',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bankIbanTl,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'TL IBAN',
                              hintText: 'TR00 0000 0000 0000 0000 0000 00',
                            ),
                            inputFormatters: const [
                              QuoteBankDetailsInputFormatter(),
                            ],
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: TextField(
                            controller: _bankIbanUsd,
                            enabled: !_saving,
                            decoration: const InputDecoration(
                              labelText: 'USD IBAN',
                              hintText: 'TR00 0000 0000 0000 0000 0000 00',
                            ),
                            inputFormatters: const [
                              QuoteBankDetailsInputFormatter(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    TextField(
                      controller: _bankExtra,
                      enabled: !_saving,
                      minLines: 2,
                      maxLines: 5,
                      decoration: const InputDecoration(
                        labelText: 'Ek banka satırları',
                        hintText:
                            'EUR IBAN, Swift kodu veya ek hesap bilgileri',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(14),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Özel Şartlar',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Gap(8),
                    Text(
                      'Teklif PDF’inde notlardan sonra ayrı bölüm olarak yer alır.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSoft,
                      ),
                    ),
                    const Gap(14),
                    TextField(
                      controller: _terms,
                      enabled: !_saving,
                      minLines: 6,
                      maxLines: 14,
                      decoration: const InputDecoration(
                        hintText:
                            'Örn: Teslimat 10 iş günüdür.\nFiyatlar geçerlilik tarihine kadar geçerlidir.\nÖdeme: %30 peşin, %70 sevkiyat öncesi.',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Ayarlar yüklenemedi: $error'),
                const Gap(12),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(quoteDocumentSettingsProvider),
                  child: const Text('Yeniden dene'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
