import 'dart:convert';

class MutakabatUnitPrices {
  const MutakabatUnitPrices({
    this.bankTiers = const {},
    this.ykbTiers = const {},
    this.gmp3 = 0,
    this.tsm = 0,
    this.maxBankTier = 7,
  });

  final Map<int, double> bankTiers;
  final Map<int, double> ykbTiers;
  final double gmp3;
  final double tsm;
  final int maxBankTier;

  factory MutakabatUnitPrices.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MutakabatUnitPrices();
    Map<int, double> parseTiers(dynamic raw) {
      if (raw is! Map) return {};
      return raw.map(
        (key, value) => MapEntry(
          int.tryParse(key.toString()) ?? 0,
          (value is num ? value.toDouble() : double.tryParse('$value')) ?? 0,
        ),
      )..removeWhere((key, _) => key <= 0);
    }

    return MutakabatUnitPrices(
      bankTiers: parseTiers(json['bankTiers'] ?? json['bank_tiers']),
      ykbTiers: parseTiers(json['ykbTiers'] ?? json['ykb_tiers']),
      gmp3: (json['gmp3'] as num?)?.toDouble() ?? 0,
      tsm: (json['tsm'] as num?)?.toDouble() ?? 0,
      maxBankTier: (json['maxBankTier'] as num?)?.toInt() ??
          (json['max_bank_tier'] as num?)?.toInt() ??
          7,
    );
  }

  Map<String, dynamic> toJson() => {
    'bankTiers': bankTiers.map((k, v) => MapEntry('$k', v)),
    'ykbTiers': ykbTiers.map((k, v) => MapEntry('$k', v)),
    'gmp3': gmp3,
    'tsm': tsm,
    'maxBankTier': maxBankTier,
  };

  MutakabatUnitPrices copyWith({
    Map<int, double>? bankTiers,
    Map<int, double>? ykbTiers,
    double? gmp3,
    double? tsm,
    int? maxBankTier,
  }) {
    return MutakabatUnitPrices(
      bankTiers: bankTiers ?? this.bankTiers,
      ykbTiers: ykbTiers ?? this.ykbTiers,
      gmp3: gmp3 ?? this.gmp3,
      tsm: tsm ?? this.tsm,
      maxBankTier: maxBankTier ?? this.maxBankTier,
    );
  }
}

class MutakabatTotals {
  const MutakabatTotals({
    this.microviseBank = 0,
    this.worldlineBank = 0,
    this.worldlineIntegrations = 0,
    this.microviseGrand = 0,
    this.worldlineGrand = 0,
  });

  final double microviseBank;
  final double worldlineBank;
  final double worldlineIntegrations;
  final double microviseGrand;
  final double worldlineGrand;

  factory MutakabatTotals.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MutakabatTotals();
    double n(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return MutakabatTotals(
      microviseBank: n(json['microviseBank']),
      worldlineBank: n(json['worldlineBank']),
      worldlineIntegrations: n(json['worldlineIntegrations']),
      microviseGrand: n(json['microviseGrand']),
      worldlineGrand: n(json['worldlineGrand']),
    );
  }
}

class MutakabatLineItem {
  const MutakabatLineItem({
    required this.group,
    required this.bankTier,
    required this.label,
    required this.quantity,
    required this.unitPrice,
    required this.microviseAmount,
    required this.worldlineAmount,
  });

  final String group;
  final int bankTier;
  final String label;
  final int quantity;
  final double unitPrice;
  final double microviseAmount;
  final double worldlineAmount;

  factory MutakabatLineItem.fromJson(Map<String, dynamic> json) {
    double n(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return MutakabatLineItem(
      group: json['group']?.toString() ?? '',
      bankTier: (json['bankTier'] as num?)?.toInt() ?? 0,
      label: json['label']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: n(json['unitPrice']),
      microviseAmount: n(json['microviseAmount']),
      worldlineAmount: n(json['worldlineAmount']),
    );
  }
}

class MutakabatIntegrationItem {
  const MutakabatIntegrationItem({
    required this.key,
    required this.label,
    required this.quantity,
    required this.unitPrice,
    required this.worldlineAmount,
  });

  final String key;
  final String label;
  final int quantity;
  final double unitPrice;
  final double worldlineAmount;

  factory MutakabatIntegrationItem.fromJson(Map<String, dynamic> json) {
    double n(dynamic value) =>
        value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    return MutakabatIntegrationItem(
      key: json['key']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: n(json['unitPrice']),
      worldlineAmount: n(json['worldlineAmount']),
    );
  }
}

class MutakabatSummary {
  const MutakabatSummary({
    this.ingenicoCounts = const {},
    this.paxCounts = const {},
    this.ykbCounts = const {},
    this.gmp3Count = 0,
    this.tsmCount = 0,
    this.lineItems = const [],
    this.integrations = const [],
    this.totals = const MutakabatTotals(),
    this.rowCounts = const {},
  });

  final Map<int, int> ingenicoCounts;
  final Map<int, int> paxCounts;
  final Map<int, int> ykbCounts;
  final int gmp3Count;
  final int tsmCount;
  final List<MutakabatLineItem> lineItems;
  final List<MutakabatIntegrationItem> integrations;
  final MutakabatTotals totals;
  final Map<String, int> rowCounts;

  static Map<int, int> _parseTierCounts(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(
        int.tryParse(key.toString()) ?? 0,
        (value as num?)?.toInt() ?? 0,
      ),
    )..removeWhere((key, _) => key <= 0);
  }

  factory MutakabatSummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MutakabatSummary();
    final countsRaw = json['rowCounts'];
    final counts = <String, int>{};
    if (countsRaw is Map) {
      countsRaw.forEach((key, value) {
        counts[key.toString()] = (value as num?)?.toInt() ?? 0;
      });
    }
    final gmp3Raw = json['gmp3'];
    final tsmRaw = json['tsm'];
    return MutakabatSummary(
      ingenicoCounts: _parseTierCounts(json['ingenico']),
      paxCounts: _parseTierCounts(json['pax']),
      ykbCounts: _parseTierCounts(json['ykb']),
      gmp3Count: gmp3Raw is Map
          ? (gmp3Raw['count'] as num?)?.toInt() ?? 0
          : (gmp3Raw as num?)?.toInt() ?? 0,
      tsmCount: tsmRaw is Map
          ? (tsmRaw['count'] as num?)?.toInt() ?? 0
          : (tsmRaw as num?)?.toInt() ?? 0,
      lineItems: ((json['lineItems'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (e) => MutakabatLineItem.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
      integrations: ((json['integrations'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (e) => MutakabatIntegrationItem.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList(growable: false),
      totals: MutakabatTotals.fromJson(
        (json['totals'] as Map?)?.cast<String, dynamic>(),
      ),
      rowCounts: counts,
    );
  }

  Map<String, dynamic> toJson() => {
    'ingenico': ingenicoCounts.map((k, v) => MapEntry('$k', v)),
    'pax': paxCounts.map((k, v) => MapEntry('$k', v)),
    'ykb': ykbCounts.map((k, v) => MapEntry('$k', v)),
    'gmp3': {'count': gmp3Count},
    'tsm': {'count': tsmCount},
    'lineItems': lineItems
        .map(
          (item) => {
            'group': item.group,
            'bankTier': item.bankTier,
            'label': item.label,
            'quantity': item.quantity,
            'unitPrice': item.unitPrice,
            'microviseAmount': item.microviseAmount,
            'worldlineAmount': item.worldlineAmount,
          },
        )
        .toList(growable: false),
    'integrations': integrations
        .map(
          (item) => {
            'key': item.key,
            'label': item.label,
            'quantity': item.quantity,
            'unitPrice': item.unitPrice,
            'worldlineAmount': item.worldlineAmount,
          },
        )
        .toList(growable: false),
    'totals': {
      'microviseBank': totals.microviseBank,
      'worldlineBank': totals.worldlineBank,
      'worldlineIntegrations': totals.worldlineIntegrations,
      'microviseGrand': totals.microviseGrand,
      'worldlineGrand': totals.worldlineGrand,
    },
    'rowCounts': rowCounts,
  };
}

class MutakabatSourceFiles {
  const MutakabatSourceFiles({
    this.bankFileName,
    this.gmp3FileName,
    this.tsmFileName,
  });

  final String? bankFileName;
  final String? gmp3FileName;
  final String? tsmFileName;

  factory MutakabatSourceFiles.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const MutakabatSourceFiles();
    return MutakabatSourceFiles(
      bankFileName: json['bankFileName']?.toString(),
      gmp3FileName: json['gmp3FileName']?.toString(),
      tsmFileName: json['tsmFileName']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (bankFileName != null) 'bankFileName': bankFileName,
    if (gmp3FileName != null) 'gmp3FileName': gmp3FileName,
    if (tsmFileName != null) 'tsmFileName': tsmFileName,
  };
}

class MutakabatRecord {
  const MutakabatRecord({
    required this.id,
    required this.periodYear,
    required this.periodMonth,
    required this.title,
    required this.notes,
    required this.status,
    required this.unitPrices,
    required this.summary,
    required this.sourceFiles,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
    this.detailSheets,
  });

  final String id;
  final int periodYear;
  final int periodMonth;
  final String title;
  final String notes;
  final String status;
  final MutakabatUnitPrices unitPrices;
  final MutakabatSummary summary;
  final MutakabatSourceFiles sourceFiles;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final Map<String, dynamic>? detailSheets;

  String get periodLabel {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    if (periodMonth < 1 || periodMonth > 12) {
      return '$periodYear / $periodMonth';
    }
    return '${months[periodMonth - 1]} $periodYear';
  }

  factory MutakabatRecord.fromJson(Map<String, dynamic> json) {
    return MutakabatRecord(
      id: json['id']?.toString() ?? '',
      periodYear: (json['period_year'] as num?)?.toInt() ?? 0,
      periodMonth: (json['period_month'] as num?)?.toInt() ?? 0,
      title: json['title']?.toString() ?? '',
      notes: json['notes']?.toString() ?? '',
      status: json['status']?.toString() ?? 'draft',
      unitPrices: MutakabatUnitPrices.fromJson(
        (json['unit_prices'] as Map?)?.cast<String, dynamic>(),
      ),
      summary: MutakabatSummary.fromJson(
        (json['summary'] as Map?)?.cast<String, dynamic>(),
      ),
      sourceFiles: MutakabatSourceFiles.fromJson(
        (json['source_files'] as Map?)?.cast<String, dynamic>(),
      ),
      isActive: json['is_active'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      detailSheets: (json['detail_sheets'] as Map?)?.cast<String, dynamic>(),
    );
  }

  Map<String, dynamic> toUpsertJson({
    required MutakabatSummary summary,
    Map<String, dynamic>? detailSheets,
    MutakabatSourceFiles? sourceFiles,
  }) {
    return {
      'period_year': periodYear,
      'period_month': periodMonth,
      'title': title,
      'notes': notes,
      'status': status,
      'unit_prices': unitPrices.toJson(),
      'summary': summary.toJson(),
      if (detailSheets != null) 'detail_sheets': detailSheets,
      'source_files': (sourceFiles ?? this.sourceFiles).toJson(),
      'is_active': isActive,
    };
  }
}

class MutakabatPriceSetting {
  const MutakabatPriceSetting({
    required this.id,
    required this.name,
    required this.unitPrices,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final MutakabatUnitPrices unitPrices;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory MutakabatPriceSetting.fromJson(Map<String, dynamic> json) {
    return MutakabatPriceSetting(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      unitPrices: MutakabatUnitPrices.fromJson(
        (json['unit_prices'] as Map?)?.cast<String, dynamic>(),
      ),
      isActive: json['is_active'] == true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}

String encodeFileToBase64(List<int> bytes) => base64Encode(bytes);
