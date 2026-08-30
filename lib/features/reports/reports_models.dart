double _n(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _i(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

List<Map<String, dynamic>> _maps(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

class ReportBucket {
  const ReportBucket({
    required this.key,
    required this.count,
    required this.amount,
    this.qty = 0,
    this.vat = 0,
    this.name,
    this.type,
    this.open = 0,
    this.inProgress = 0,
    this.done = 0,
  });

  final String key;
  final String? name;
  final String? type;
  final int count;
  final double amount;
  final double qty;
  final double vat;
  final int open;
  final int inProgress;
  final int done;

  String get label => (name ?? key).trim().isEmpty ? '—' : (name ?? key);

  factory ReportBucket.fromJson(Map<String, dynamic> json) {
    return ReportBucket(
      key: (json['key'] ?? json['name'] ?? json['type'] ?? '').toString(),
      name: json['name']?.toString(),
      type: json['type']?.toString(),
      count: _i(json['count']),
      amount: _n(json['amount']),
      qty: _n(json['qty']),
      vat: _n(json['vat']),
      open: _i(json['open']),
      inProgress: _i(json['inProgress'] ?? json['in_progress']),
      done: _i(json['done']),
    );
  }
}

class ReportPoint {
  const ReportPoint({required this.day, required this.value});

  final DateTime day;
  final double value;

  factory ReportPoint.fromJson(Map<String, dynamic> json) {
    return ReportPoint(
      day: DateTime.tryParse(json['day']?.toString() ?? '') ?? DateTime.now(),
      value: _n(json['value']),
    );
  }
}

class ReportUser {
  const ReportUser({
    required this.id,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String? fullName;
  final String? role;

  factory ReportUser.fromJson(Map<String, dynamic> json) {
    return ReportUser(
      id: json['id'].toString(),
      fullName: json['full_name']?.toString(),
      role: json['role']?.toString(),
    );
  }
}

class ReportPerson {
  const ReportPerson({
    required this.id,
    required this.name,
    required this.role,
    required this.workOrders,
    required this.workOrdersDone,
    required this.payments,
    required this.invoices,
    required this.quotes,
    required this.services,
  });

  final String id;
  final String name;
  final String role;
  final int workOrders;
  final int workOrdersDone;
  final double payments;
  final int invoices;
  final int quotes;
  final int services;

  factory ReportPerson.fromJson(Map<String, dynamic> json) {
    return ReportPerson(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Personel',
      role: json['role']?.toString() ?? '',
      workOrders: _i(json['workOrders'] ?? json['work_orders']),
      workOrdersDone: _i(json['workOrdersDone'] ?? json['work_orders_done']),
      payments: _n(json['payments']),
      invoices: _i(json['invoices']),
      quotes: _i(json['quotes']),
      services: _i(json['services']),
    );
  }
}

class ReportsKpis {
  const ReportsKpis({
    required this.salesAmount,
    required this.prevSalesAmount,
    required this.salesCount,
    required this.salesVat,
    required this.salesPaid,
    required this.purchaseAmount,
    required this.purchaseCount,
    required this.purchaseVat,
    required this.collectionsAmount,
    required this.prevCollectionsAmount,
    required this.collectionsCount,
    required this.paymentsAmount,
    required this.prevPaymentsAmount,
    required this.paymentsCount,
    required this.receivableAmount,
    required this.receivableCount,
    required this.payableAmount,
    required this.payableCount,
    required this.quoteAmount,
    required this.prevQuoteAmount,
    required this.quoteCount,
    required this.quoteWonCount,
    required this.quoteWonAmount,
    required this.quoteLostCount,
    required this.quoteConvertedCount,
    required this.quoteConversionRate,
    required this.customersActive,
    required this.customersTotal,
    required this.customersNew,
    required this.workOrdersCreated,
    required this.prevWorkOrdersCreated,
    required this.workOrdersOpen,
    required this.workOrdersInProgress,
    required this.workOrdersDone,
    required this.serviceCount,
    required this.serviceAmount,
    required this.products,
    required this.lowStock,
    required this.linesAvailable,
    required this.linesConsumed,
    required this.licensesExpiring,
    required this.linesExpiring,
    required this.posCollected,
    required this.posPending,
    required this.posPendingCount,
    required this.posCount,
    required this.recurringPlans,
    required this.recurringMonthly,
    required this.recurringRuns,
    required this.financeIn,
    required this.financeOut,
    required this.financeCount,
    required this.applications,
    required this.scraps,
    required this.faults,
    required this.transfers,
    required this.mutakabat,
  });

  final double salesAmount;
  final double prevSalesAmount;
  final int salesCount;
  final double salesVat;
  final double salesPaid;
  final double purchaseAmount;
  final int purchaseCount;
  final double purchaseVat;
  final double collectionsAmount;
  final double prevCollectionsAmount;
  final int collectionsCount;
  final double paymentsAmount;
  final double prevPaymentsAmount;
  final int paymentsCount;
  final double receivableAmount;
  final int receivableCount;
  final double payableAmount;
  final int payableCount;
  final double quoteAmount;
  final double prevQuoteAmount;
  final int quoteCount;
  final int quoteWonCount;
  final double quoteWonAmount;
  final int quoteLostCount;
  final int quoteConvertedCount;
  final double quoteConversionRate;
  final int customersActive;
  final int customersTotal;
  final int customersNew;
  final int workOrdersCreated;
  final int prevWorkOrdersCreated;
  final int workOrdersOpen;
  final int workOrdersInProgress;
  final int workOrdersDone;
  final int serviceCount;
  final double serviceAmount;
  final int products;
  final int lowStock;
  final int linesAvailable;
  final int linesConsumed;
  final int licensesExpiring;
  final int linesExpiring;
  final double posCollected;
  final double posPending;
  final int posPendingCount;
  final int posCount;
  final int recurringPlans;
  final double recurringMonthly;
  final int recurringRuns;
  final double financeIn;
  final double financeOut;
  final int financeCount;
  final int applications;
  final int scraps;
  final int faults;
  final int transfers;
  final int mutakabat;

  factory ReportsKpis.fromJson(Map<String, dynamic> json) {
    return ReportsKpis(
      salesAmount: _n(json['salesAmount']),
      prevSalesAmount: _n(json['prevSalesAmount']),
      salesCount: _i(json['salesCount']),
      salesVat: _n(json['salesVat']),
      salesPaid: _n(json['salesPaid']),
      purchaseAmount: _n(json['purchaseAmount']),
      purchaseCount: _i(json['purchaseCount']),
      purchaseVat: _n(json['purchaseVat']),
      collectionsAmount: _n(json['collectionsAmount']),
      prevCollectionsAmount: _n(json['prevCollectionsAmount']),
      collectionsCount: _i(json['collectionsCount']),
      paymentsAmount: _n(json['paymentsAmount']),
      prevPaymentsAmount: _n(json['prevPaymentsAmount']),
      paymentsCount: _i(json['paymentsCount']),
      receivableAmount: _n(json['receivableAmount']),
      receivableCount: _i(json['receivableCount']),
      payableAmount: _n(json['payableAmount']),
      payableCount: _i(json['payableCount']),
      quoteAmount: _n(json['quoteAmount']),
      prevQuoteAmount: _n(json['prevQuoteAmount']),
      quoteCount: _i(json['quoteCount']),
      quoteWonCount: _i(json['quoteWonCount']),
      quoteWonAmount: _n(json['quoteWonAmount']),
      quoteLostCount: _i(json['quoteLostCount']),
      quoteConvertedCount: _i(json['quoteConvertedCount']),
      quoteConversionRate: _n(json['quoteConversionRate']),
      customersActive: _i(json['customersActive']),
      customersTotal: _i(json['customersTotal']),
      customersNew: _i(json['customersNew']),
      workOrdersCreated: _i(json['workOrdersCreated']),
      prevWorkOrdersCreated: _i(json['prevWorkOrdersCreated']),
      workOrdersOpen: _i(json['workOrdersOpen']),
      workOrdersInProgress: _i(json['workOrdersInProgress']),
      workOrdersDone: _i(json['workOrdersDone']),
      serviceCount: _i(json['serviceCount']),
      serviceAmount: _n(json['serviceAmount']),
      products: _i(json['products']),
      lowStock: _i(json['lowStock']),
      linesAvailable: _i(json['linesAvailable']),
      linesConsumed: _i(json['linesConsumed']),
      licensesExpiring: _i(json['licensesExpiring']),
      linesExpiring: _i(json['linesExpiring']),
      posCollected: _n(json['posCollected']),
      posPending: _n(json['posPending']),
      posPendingCount: _i(json['posPendingCount']),
      posCount: _i(json['posCount']),
      recurringPlans: _i(json['recurringPlans']),
      recurringMonthly: _n(json['recurringMonthly']),
      recurringRuns: _i(json['recurringRuns']),
      financeIn: _n(json['financeIn']),
      financeOut: _n(json['financeOut']),
      financeCount: _i(json['financeCount']),
      applications: _i(json['applications']),
      scraps: _i(json['scraps']),
      faults: _i(json['faults']),
      transfers: _i(json['transfers']),
      mutakabat: _i(json['mutakabat']),
    );
  }

  factory ReportsKpis.empty() => ReportsKpis.fromJson(const {});
}

class SystemReports {
  const SystemReports({
    required this.from,
    required this.to,
    required this.kpis,
    required this.salesSeries,
    required this.collectionsSeries,
    required this.paymentsSeries,
    required this.invoiceByStatus,
    required this.invoiceByType,
    required this.invoiceByEStatus,
    required this.invoiceTopCustomers,
    required this.invoiceTopProducts,
    required this.paymentByMethod,
    required this.paymentTopCustomers,
    required this.quoteByStatus,
    required this.quoteTopCustomers,
    required this.customersByCity,
    required this.workOrderByStatus,
    required this.workOrderByUser,
    required this.serviceByStatus,
    required this.serviceByPriority,
    required this.applicationByBrand,
    required this.applicationByApproval,
    required this.financeAccounts,
    required this.financeByType,
    required this.lowStock,
    required this.personnel,
  });

  final DateTime from;
  final DateTime to;
  final ReportsKpis kpis;
  final List<ReportPoint> salesSeries;
  final List<ReportPoint> collectionsSeries;
  final List<ReportPoint> paymentsSeries;
  final List<ReportBucket> invoiceByStatus;
  final List<ReportBucket> invoiceByType;
  final List<ReportBucket> invoiceByEStatus;
  final List<ReportBucket> invoiceTopCustomers;
  final List<ReportBucket> invoiceTopProducts;
  final List<ReportBucket> paymentByMethod;
  final List<ReportBucket> paymentTopCustomers;
  final List<ReportBucket> quoteByStatus;
  final List<ReportBucket> quoteTopCustomers;
  final List<ReportBucket> customersByCity;
  final List<ReportBucket> workOrderByStatus;
  final List<ReportBucket> workOrderByUser;
  final List<ReportBucket> serviceByStatus;
  final List<ReportBucket> serviceByPriority;
  final List<ReportBucket> applicationByBrand;
  final List<ReportBucket> applicationByApproval;
  final List<ReportBucket> financeAccounts;
  final List<ReportBucket> financeByType;
  final List<ReportBucket> lowStock;
  final List<ReportPerson> personnel;

  factory SystemReports.empty() => SystemReports.fromJson(const {});

  factory SystemReports.fromJson(Map<String, dynamic> json) {
    final range = (json['range'] as Map?)?.cast<String, dynamic>() ?? const {};
    final kpis = (json['kpis'] as Map?)?.cast<String, dynamic>() ?? const {};
    final series = (json['series'] as Map?)?.cast<String, dynamic>() ?? const {};
    final invoices = (json['invoices'] as Map?)?.cast<String, dynamic>() ?? const {};
    final payments = (json['payments'] as Map?)?.cast<String, dynamic>() ?? const {};
    final quotes = (json['quotes'] as Map?)?.cast<String, dynamic>() ?? const {};
    final customers =
        (json['customers'] as Map?)?.cast<String, dynamic>() ?? const {};
    final workOrders =
        (json['workOrders'] as Map?)?.cast<String, dynamic>() ?? const {};
    final service = (json['service'] as Map?)?.cast<String, dynamic>() ?? const {};
    final forms = (json['forms'] as Map?)?.cast<String, dynamic>() ?? const {};
    final finance = (json['finance'] as Map?)?.cast<String, dynamic>() ?? const {};
    final stock = (json['stock'] as Map?)?.cast<String, dynamic>() ?? const {};

    List<ReportPoint> points(dynamic raw) => _maps(raw)
        .map(ReportPoint.fromJson)
        .toList(growable: false);
    List<ReportBucket> buckets(dynamic raw) => _maps(raw)
        .map(ReportBucket.fromJson)
        .toList(growable: false);

    return SystemReports(
      from: DateTime.tryParse(range['from']?.toString() ?? '') ?? DateTime.now(),
      to: DateTime.tryParse(range['to']?.toString() ?? '') ?? DateTime.now(),
      kpis: ReportsKpis.fromJson(kpis),
      salesSeries: points(series['sales']),
      collectionsSeries: points(series['collections']),
      paymentsSeries: points(series['payments']),
      invoiceByStatus: buckets(invoices['byStatus']),
      invoiceByType: buckets(invoices['byType']),
      invoiceByEStatus: buckets(invoices['byEStatus']),
      invoiceTopCustomers: buckets(invoices['topCustomers']),
      invoiceTopProducts: buckets(invoices['topProducts']),
      paymentByMethod: buckets(payments['byMethod']),
      paymentTopCustomers: buckets(payments['topCustomers']),
      quoteByStatus: buckets(quotes['byStatus']),
      quoteTopCustomers: buckets(quotes['topCustomers']),
      customersByCity: buckets(customers['byCity']),
      workOrderByStatus: buckets(workOrders['byStatus']),
      workOrderByUser: buckets(workOrders['byUser']),
      serviceByStatus: buckets(service['byStatus']),
      serviceByPriority: buckets(service['byPriority']),
      applicationByBrand: buckets(forms['byBrand']),
      applicationByApproval: buckets(forms['byApproval']),
      financeAccounts: buckets(finance['accounts']),
      financeByType: buckets(finance['byType']),
      lowStock: buckets(stock['lowStock']),
      personnel: _maps(json['personnel']).map(ReportPerson.fromJson).toList(),
    );
  }
}

enum ReportsPreset {
  last7Days,
  last30Days,
  thisMonth,
  lastMonth,
  thisYear,
  custom,
}

enum ReportsSection {
  overview,
  invoices,
  collections,
  quotes,
  customers,
  stock,
  workOrders,
  service,
  forms,
  finance,
  personnel,
}

extension ReportsSectionX on ReportsSection {
  String get path => switch (this) {
    ReportsSection.overview => 'ozet',
    ReportsSection.invoices => 'fatura',
    ReportsSection.collections => 'tahsilat',
    ReportsSection.quotes => 'teklif',
    ReportsSection.customers => 'cari',
    ReportsSection.stock => 'stok',
    ReportsSection.workOrders => 'is-emirleri',
    ReportsSection.service => 'servis',
    ReportsSection.forms => 'formlar',
    ReportsSection.finance => 'finans',
    ReportsSection.personnel => 'personel',
  };

  String get label => switch (this) {
    ReportsSection.overview => 'Özet',
    ReportsSection.invoices => 'Satış & Fatura',
    ReportsSection.collections => 'Tahsilat',
    ReportsSection.quotes => 'Teklif',
    ReportsSection.customers => 'Cari',
    ReportsSection.stock => 'Stok & Hat',
    ReportsSection.workOrders => 'İş Emirleri',
    ReportsSection.service => 'Servis',
    ReportsSection.forms => 'Formlar',
    ReportsSection.finance => 'Finans',
    ReportsSection.personnel => 'Personel',
  };

  static ReportsSection fromPath(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    return ReportsSection.values.firstWhere(
      (e) => e.path == value,
      orElse: () => ReportsSection.overview,
    );
  }
}

class ReportsFilters {
  const ReportsFilters({
    required this.preset,
    required this.userId,
    this.customFrom,
    this.customTo,
  });

  final ReportsPreset preset;
  final String? userId;
  final DateTime? customFrom;
  final DateTime? customTo;

  factory ReportsFilters.last30Days() =>
      const ReportsFilters(preset: ReportsPreset.last30Days, userId: null);

  ReportsFilters copyWith({
    ReportsPreset? preset,
    String? userId,
    DateTime? customFrom,
    DateTime? customTo,
    bool clearUser = false,
  }) {
    return ReportsFilters(
      preset: preset ?? this.preset,
      userId: clearUser ? null : (userId ?? this.userId),
      customFrom: customFrom ?? this.customFrom,
      customTo: customTo ?? this.customTo,
    );
  }

  DateTime get from {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (preset) {
      ReportsPreset.last7Days => today.subtract(const Duration(days: 6)),
      ReportsPreset.last30Days => today.subtract(const Duration(days: 29)),
      ReportsPreset.thisMonth => DateTime(now.year, now.month, 1),
      ReportsPreset.lastMonth => DateTime(now.year, now.month - 1, 1),
      ReportsPreset.thisYear => DateTime(now.year, 1, 1),
      ReportsPreset.custom =>
        customFrom ?? today.subtract(const Duration(days: 29)),
    };
  }

  DateTime get to {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (preset) {
      ReportsPreset.lastMonth => DateTime(now.year, now.month, 0),
      ReportsPreset.custom => customTo ?? today,
      _ => today,
    };
  }
}
