create or replace function public.has_action_permission(p_action text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and (
        u.role = 'admin'
        or p_action = any(coalesce(u.action_permissions, '{}'::text[]))
      )
  );
$$;

drop policy if exists "work_orders_delete_authorized" on public.work_orders;
create policy "work_orders_delete_authorized"
on public.work_orders
for delete
to authenticated
using (
  public.has_action_permission('kalici_silme')
);

drop policy if exists "payments_delete_authorized" on public.payments;
create policy "payments_delete_authorized"
on public.payments
for delete
to authenticated
using (
  public.has_action_permission('kalici_silme')
);
