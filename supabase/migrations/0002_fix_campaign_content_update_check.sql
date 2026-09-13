-- Fixes BUG-05: campaign_content_update_workflow had no explicit WITH CHECK, so
-- Postgres reused USING to validate the *new* row too. That accidentally blocked a
-- Contributor from submitting their own draft for approval, because the new row's
-- status ("pending_approval") no longer satisfied "status in ('draft', 'rejected')".
-- See supabase/migrations/0001_init.sql for the full policy history/comment.

drop policy if exists campaign_content_update_workflow on public.campaign_content;

create policy campaign_content_update_workflow on public.campaign_content
  for update using (
    public.is_admin()
    or (created_by = auth.uid() and status in ('draft', 'rejected'))
    or public.has_role('approver')
    or public.has_role('publisher')
  )
  with check (
    public.is_admin()
    or created_by = auth.uid()
    or public.has_role('approver')
    or public.has_role('publisher')
  );
