import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../../core/api/api_client.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/storage/app_cache.dart';
import '../../core/supabase/supabase_providers.dart';
import 'work_order_model.dart';

final workOrdersBoardProvider =
    AsyncNotifierProvider<WorkOrdersBoardNotifier, List<WorkOrder>>(
      WorkOrdersBoardNotifier.new,
    );

class WorkOrdersBoardNotifier extends AsyncNotifier<List<WorkOrder>> {
  String? _cacheKey;
  Timer? _liveTimer;
  bool _liveRefreshInFlight = false;

  @override
  Future<List<WorkOrder>> build() async {
    final apiClient = ref.watch(apiClientProvider);
    final client = ref.watch(supabaseClientProvider);

    _cacheKey = _makeCacheKey(apiClient, client);
    final cached = _tryReadCache();
    if (cached != null) {
      _ensureLiveRefresh();
      unawaited(_refreshFromRemoteAndCache());
      return cached;
    }

    if (apiClient != null) {
      final initial = await _fetchApi(pageSize: 200);
      unawaited(_persistCache(initial));
      _ensureLiveRefresh();
      unawaited(_refreshFromRemoteAndCache());
      return initial;
    }

    if (client == null) return const [];
    final items = await _fetchSupabase();
    unawaited(_persistCache(items));
    _ensureLiveRefresh();
    return items;
  }

  void _ensureLiveRefresh() {
    if (_liveTimer != null) return;
    ref.onDispose(() {
      _liveTimer?.cancel();
      _liveTimer = null;
    });

    const interval = Duration(seconds: 6);
    _liveTimer = Timer.periodic(interval, (_) {
      if (!ref.mounted) return;
      unawaited(_refreshFromRemoteAndCache());
    });
  }

  Future<List<WorkOrder>> _fetchApi({required int pageSize}) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return const [];
    try {
      final response = await apiClient
          .getJson(
            '/work-orders',
            queryParameters: {'pageSize': '$pageSize'},
          )
          .timeout(const Duration(seconds: 30));
      return await _mapApiWorkOrdersWithPaymentFallback(response['items']);
    } on TimeoutException {
      final response = await apiClient
          .getJson(
            '/work-orders',
            queryParameters: {'pageSize': '$pageSize'},
          )
          .timeout(const Duration(seconds: 30));
      return await _mapApiWorkOrdersWithPaymentFallback(response['items']);
    }
  }

  Future<List<WorkOrder>> _mapApiWorkOrdersWithPaymentFallback(Object? raw) async {
    final maps = ((raw as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);

    if (maps.isEmpty) return const [];

    final hasPaymentRequired = maps.any((m) => m.containsKey('payment_required'));
    if (hasPaymentRequired) {
      return maps.map(WorkOrder.fromJson).toList(growable: false);
    }

    final client = ref.read(supabaseClientProvider);
    if (client == null) {
      return maps.map(WorkOrder.fromJson).toList(growable: false);
    }

    final ids = maps
        .map((m) => m['id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (ids.isEmpty) {
      return maps.map(WorkOrder.fromJson).toList(growable: false);
    }

    final paymentById = <String, bool>{};
    try {
      final rows = await client
          .from('work_orders')
          .select('id,payment_required')
          .inFilter('id', ids)
          .then((value) => (value as List).cast<Map>());

      for (final row in rows) {
        final id = row['id']?.toString();
        final value = row['payment_required'];
        if (id == null || id.isEmpty) continue;
        if (value is bool) paymentById[id] = value;
      }
    } catch (_) {}

    final merged = maps
        .map(
          (m) => WorkOrder.fromJson({
            ...m,
            if (m['id'] != null) 'payment_required': paymentById[m['id']?.toString()],
          }),
        )
        .toList(growable: false);

    return merged;
  }

  Future<List<WorkOrder>> _fetchSupabase() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return const [];

    final profile = await ref.watch(currentUserProfileProvider.future);
    final isAdmin = profile?.role == 'admin';

    final baseSelect =
        'id,title,description,address,city,status,is_active,payment_required,customer_id,branch_id,assigned_to,scheduled_date,created_at,closed_at,work_order_type_id,contact_phone,location_link,close_notes,sort_order,customers(name),branches(name),work_order_types(name)';

    var q = client.from('work_orders').select(baseSelect);

    if (!isAdmin) {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return const [];
      q = q.eq('assigned_to', userId);
    }

    Object rows;
    try {
      rows = await q.order('sort_order').order('created_at', ascending: false);
    } catch (e) {
      final message = e.toString();
      if (!message.contains('payment_required')) rethrow;
      var fallback = client.from('work_orders').select(
            baseSelect.replaceAll('payment_required,', ''),
          );
      if (!isAdmin) {
        final userId = client.auth.currentUser?.id;
        if (userId == null) return const [];
        fallback = fallback.eq('assigned_to', userId);
      }
      rows = await fallback.order('sort_order').order('created_at', ascending: false);
    }

    final rawRows = (rows as List)
        .cast<Map<String, dynamic>>()
        .toList(growable: false);
    final doneIds = rawRows
        .where((row) => row['status']?.toString() == 'done')
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toList(growable: false);

    final paymentRows = doneIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await client
            .from('payments')
            .select(
              'work_order_id,amount,currency,description,paid_at,payment_method,is_active',
            )
            .eq('is_active', true)
            .inFilter('work_order_id', doneIds)
            .order('paid_at', ascending: false)
            .then((value) => (value as List).cast<Map<String, dynamic>>());

    final paymentsByWorkOrder = <String, List<Map<String, dynamic>>>{};
    for (final row in paymentRows) {
      final workOrderId = row['work_order_id']?.toString();
      if (workOrderId == null || workOrderId.isEmpty) continue;
      paymentsByWorkOrder.update(
        workOrderId,
        (items) => [...items, row],
        ifAbsent: () => [row],
      );
    }

    final items = rawRows.map((map) {
      final customers = map['customers'] as Map<String, dynamic>?;
      final branches = map['branches'] as Map<String, dynamic>?;
      final workOrderTypes =
          map['work_order_types'] as Map<String, dynamic>?;
      final workOrderId = map['id']?.toString() ?? '';
      return WorkOrder.fromJson({
        ...map,
        'customer_name': customers?['name'],
        'branch_name': branches?['name'],
        'work_order_type_name': workOrderTypes?['name'],
        'payments': paymentsByWorkOrder[workOrderId] ?? const [],
      });
    }).toList(growable: false);

    final statusRank = {'open': 0, 'in_progress': 1, 'done': 2};
    final sortedItems = [...items]
      ..sort((a, b) {
        final statusCompare = (statusRank[a.status] ?? 99).compareTo(
          statusRank[b.status] ?? 99,
        );
        if (statusCompare != 0) return statusCompare;
        final sortCompare = a.sortOrder.compareTo(b.sortOrder);
        if (sortCompare != 0) return sortCompare;
        return 0;
      });
    return sortedItems;
  }

  List<WorkOrder>? _tryReadCache() {
    final key = _cacheKey;
    if (key == null || key.isEmpty) return null;
    final entry = AppCache.readJson<List<WorkOrder>>(
      key,
      decode: (json) {
        final list = (json as List?) ?? const [];
        return list
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .map(WorkOrder.fromJson)
            .toList(growable: false);
      },
    );
    return entry?.value;
  }

  Future<void> _persistCache(List<WorkOrder> items) async {
    final key = _cacheKey;
    if (key == null || key.isEmpty) return;
    await AppCache.writeJson(
      key,
      items.map((e) => e.toJson()).toList(growable: false),
    );
  }

  Future<void> _refreshFromRemoteAndCache() async {
    if (!ref.mounted) return;
    if (_liveRefreshInFlight) return;
    _liveRefreshInFlight = true;
    try {
      final apiClient = ref.read(apiClientProvider);
      final items =
          apiClient != null ? await _fetchApi(pageSize: 200) : await _fetchSupabase();
      if (!ref.mounted) return;
      state = AsyncData(items);
      await _persistCache(items);
    } catch (_) {
    } finally {
      _liveRefreshInFlight = false;
    }
  }

  String _makeCacheKey(ApiClient? apiClient, dynamic supabaseClient) {
    final token = ref.read(accessTokenProvider) ?? '';
    final tokenHash = _hashString(token);
    final base = apiClient?.baseUrl ?? 'supabase';
    final userId = supabaseClient?.auth.currentUser?.id?.toString() ?? '';
    return 'cache:v2:work_orders:$base:$userId:$tokenHash';
  }

  int _hashString(String input) {
    var hash = 0x811C9DC5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> updateStatus({
    required String workOrderId,
    required String newStatus,
  }) async {
    final current = state.asData?.value;
    if (current == null) return;

    final next = [
      for (final w in current)
        if (w.id == workOrderId) w.copyWith(status: newStatus) else w,
    ];
    state = AsyncData(next);
    unawaited(_persistCache(next));

    final apiClient = ref.read(apiClientProvider);
    if (apiClient != null) {
      try {
        await apiClient.patchJson(
          '/work-orders',
          body: {'id': workOrderId, 'status': newStatus},
        );
        return;
      } catch (_) {
        state = AsyncData(current);
        unawaited(_persistCache(current));
        return;
      }
    }

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      await client
          .from('work_orders')
          .update({'status': newStatus})
          .eq('id', workOrderId);
    } catch (_) {
      state = AsyncData(current);
      unawaited(_persistCache(current));
    }
  }

  Future<void> updatePaymentRequired({
    required String workOrderId,
    required bool paymentRequired,
  }) async {
    final current = state.asData?.value;
    if (current == null) return;

    final next = [
      for (final w in current)
        if (w.id == workOrderId)
          w.copyWith(paymentRequired: paymentRequired)
        else
          w,
    ];
    state = AsyncData(next);
    unawaited(_persistCache(next));

    final apiClient = ref.read(apiClientProvider);
    if (apiClient != null) {
      try {
        await apiClient.patchJson(
          '/work-orders',
          body: {'id': workOrderId, 'payment_required': paymentRequired},
        );
        return;
      } catch (_) {
        state = AsyncData(current);
        unawaited(_persistCache(current));
        return;
      }
    }

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      await client
          .from('work_orders')
          .update({'payment_required': paymentRequired})
          .eq('id', workOrderId);
    } catch (_) {
      state = AsyncData(current);
      unawaited(_persistCache(current));
    }
  }

  Future<void> reorderOpenOrders(List<WorkOrder> reorderedOpenOrders) async {
    final current = state.asData?.value;
    if (current == null) return;

    final openIds = reorderedOpenOrders.map((item) => item.id).toSet();
    final reordered = [
      for (final item in reorderedOpenOrders)
        item.copyWith(sortOrder: reorderedOpenOrders.indexOf(item)),
    ];
    final next = [
      ...reordered,
      ...current.where((item) => !openIds.contains(item.id)),
    ];
    state = AsyncData(next);
    unawaited(_persistCache(next));

    final apiClient = ref.read(apiClientProvider);
    if (apiClient != null) {
      try {
        for (var i = 0; i < reorderedOpenOrders.length; i++) {
          await apiClient.patchJson(
            '/work-orders',
            body: {'id': reorderedOpenOrders[i].id, 'sort_order': i},
          );
        }
        await refresh();
        return;
      } catch (_) {
        state = AsyncData(current);
        unawaited(_persistCache(current));
        return;
      }
    }

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      for (var i = 0; i < reorderedOpenOrders.length; i++) {
        await client
            .from('work_orders')
            .update({'sort_order': i})
            .eq('id', reorderedOpenOrders[i].id);
      }
      await refresh();
    } catch (_) {
      state = AsyncData(current);
      unawaited(_persistCache(current));
    }
  }

  Future<void> setActive({
    required String workOrderId,
    required bool isActive,
  }) async {
    final current = state.asData?.value;
    if (current == null) return;

    final next = [
      for (final w in current)
        if (w.id == workOrderId) w.copyWith(isActive: isActive) else w,
    ];
    state = AsyncData(next);
    unawaited(_persistCache(next));

    final apiClient = ref.read(apiClientProvider);
    if (apiClient != null) {
      try {
        await apiClient.patchJson(
          '/work-orders',
          body: {'id': workOrderId, 'is_active': isActive},
        );
        return;
      } catch (_) {
        state = AsyncData(current);
        unawaited(_persistCache(current));
        return;
      }
    }

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      await client
          .from('work_orders')
          .update({'is_active': isActive})
          .eq('id', workOrderId);
    } catch (_) {
      state = AsyncData(current);
      unawaited(_persistCache(current));
    }
  }

  Future<void> deleteWorkOrder(String workOrderId) async {
    final current = state.asData?.value;
    if (current == null) return;
    final next = [for (final w in current) if (w.id != workOrderId) w];
    state = AsyncData(next);
    unawaited(_persistCache(next));

    final apiClient = ref.read(apiClientProvider);
    if (apiClient != null) {
      try {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'deleteWhere',
            'table': 'work_orders',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': workOrderId},
            ],
          },
        );
        return;
      } catch (_) {
        state = AsyncData(current);
        unawaited(_persistCache(current));
        return;
      }
    }

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    try {
      await client.from('work_orders').delete().eq('id', workOrderId);
    } catch (_) {
      state = AsyncData(current);
      unawaited(_persistCache(current));
    }
  }
}
