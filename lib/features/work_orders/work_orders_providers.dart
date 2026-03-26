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
          'id,title,status,is_active,customer_id,branch_id,assigned_to,scheduled_date,customers(name)',
        )
        .eq('is_active', true);

    if (!isAdmin) {
      final userId = client.auth.currentUser?.id;
      if (userId == null) return const [];
      q = q.eq('assigned_to', userId);
    }

    final rows = await q.order('created_at', ascending: false);

    return (rows as List).map((e) {
      final map = e as Map<String, dynamic>;
      final customers = map['customers'] as Map<String, dynamic>?;
      return WorkOrder.fromJson({
        ...map,
        'customer_name': customers?['name'],
      });
    }).toList(growable: false);
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
}
