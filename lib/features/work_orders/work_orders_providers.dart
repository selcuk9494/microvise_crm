import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import 'work_order_model.dart';

final workOrdersBoardProvider =
    AsyncNotifierProvider<WorkOrdersBoardNotifier, List<WorkOrder>>(
      WorkOrdersBoardNotifier.new,
    );

class WorkOrdersBoardNotifier extends AsyncNotifier<List<WorkOrder>> {
  @override
  Future<List<WorkOrder>> build() async {
    final apiClient = ref.watch(apiClientProvider);
    final client = ref.watch(supabaseClientProvider);

    if (apiClient != null) {
      final response = await apiClient.getJson('/work-orders');
      return ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(WorkOrder.fromJson)
          .toList(growable: false);
    }

    if (client == null) return const [];
    final profile = await ref.watch(currentUserProfileProvider.future);
    final isAdmin = profile?.role == 'admin';

    var q = client
        .from('work_orders')
        .select(
          'id,title,description,address,city,status,is_active,customer_id,branch_id,assigned_to,scheduled_date,created_at,closed_at,work_order_type_id,contact_phone,location_link,close_notes,sort_order,customers(name),branches(name),work_order_types(name)',
        );

    if (!isAdmin) {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return const [];
      q = q.eq('assigned_to', userId);
    }

    final rows = await q
        .order('sort_order')
        .order('created_at', ascending: false);

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
    }
  }
}
