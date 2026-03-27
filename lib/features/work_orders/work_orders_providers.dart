import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final client = ref.watch(supabaseClientProvider);
    if (client == null) return const [];
    final profile = await ref.watch(currentUserProfileProvider.future);
    final isAdmin = profile?.role == 'admin';

    var q = client
        .from('work_orders')
        .select(
          'id,title,description,city,status,is_active,customer_id,branch_id,assigned_to,scheduled_date,work_order_type_id,contact_phone,location_link,close_notes,sort_order,customers(name),branches(name),work_order_types(name),payments(amount,currency,description,paid_at,payment_method,is_active)',
        )
        .eq('is_active', true);

    if (!isAdmin) {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return const [];
      q = q.eq('assigned_to', userId);
    }

    final rows = await q
        .order('sort_order')
        .order('created_at', ascending: false);

    final items = (rows as List)
        .map((e) {
          final map = e as Map<String, dynamic>;
          final customers = map['customers'] as Map<String, dynamic>?;
          final branches = map['branches'] as Map<String, dynamic>?;
          final workOrderTypes =
              map['work_order_types'] as Map<String, dynamic>?;
          return WorkOrder.fromJson({
            ...map,
            'customer_name': customers?['name'],
            'branch_name': branches?['name'],
            'work_order_type_name': workOrderTypes?['name'],
          });
        })
        .toList(growable: false);

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

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      for (var i = 0; i < reorderedOpenOrders.length; i++) {
        await client
            .from('work_orders')
            .update({'sort_order': i})
            .eq('id', reorderedOpenOrders[i].id);
      }
    } catch (_) {
      state = AsyncData(current);
    }
  }
}
