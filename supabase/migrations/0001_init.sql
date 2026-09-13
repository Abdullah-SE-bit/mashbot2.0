-- Mashbot MVP schema
-- Implements the data model needed for the 7 FR + 3 NFR scope in docs/requirements-scope.md

-- ---------------------------------------------------------------------------
-- profiles (SRS 0240/0330/0380, 0140-0230)
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  name text not null,
  email text not null,
  roles text[] not null default '{}',
  account_type text not null default 'user' check (account_type in ('user', 'admin')),
  status text not null default 'active' check (status in ('active', 'deactivated')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'SRS 0240/0330/0380 user accounts; roles per SRS 0140-0230.';
comment on column public.profiles.roles is 'Subset of {contributor, approver, publisher}, SRS 0150/0160/0170. A user may hold more than one (SRS 0180).';

-- ---------------------------------------------------------------------------
-- campaigns (SRS 0480-0540)
-- ---------------------------------------------------------------------------
create table if not exists public.campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  start_date date,
  end_date date,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campaigns_dates_check check (end_date is null or start_date is null or end_date >= start_date)
);

-- ---------------------------------------------------------------------------
-- campaign_content (SRS 0480/0490-0500/0530/0550-0580)
-- ---------------------------------------------------------------------------
create table if not exists public.campaign_content (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns (id) on delete cascade,
  content_type text not null check (content_type in ('text', 'image')),
  body text,
  image_url text,
  status text not null default 'draft'
    check (status in ('draft', 'pending_approval', 'rejected', 'approved', 'scheduled', 'published')),
  scheduled_at timestamptz,
  created_by uuid not null references public.profiles (id),
  approved_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint campaign_content_body_or_image check (
    (content_type = 'text' and body is not null) or
    (content_type = 'image' and image_url is not null)
  )
);

comment on column public.campaign_content.scheduled_at is 'SRS 0530: schedule maps a time to a publishing action. Defaults to 00:00 on the chosen day when the user does not pick a time (enforced in application layer).';

-- ---------------------------------------------------------------------------
-- external_service_accounts (SRS 0590/0600/0610)
-- ---------------------------------------------------------------------------
create table if not exists public.external_service_accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  provider text not null check (provider in ('facebook', 'twitter', 'wordpress', 'youtube', 'flickr')),
  external_username text not null,
  status text not null default 'connected' check (status in ('connected', 'disconnected')),
  created_at timestamptz not null default now(),
  unique (user_id, provider, external_username)
);

comment on table public.external_service_accounts is 'SRS 0590-0610. Simulated association — no live OAuth handshake (see docs/assumptions.md).';

-- ---------------------------------------------------------------------------
-- updated_at triggers
-- ---------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create trigger campaigns_set_updated_at
  before update on public.campaigns
  for each row execute function public.set_updated_at();

create trigger campaign_content_set_updated_at
  before update on public.campaign_content
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- New auth user -> profile row (SRS 0240: user account creation)
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, name, email, roles, account_type)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'username', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data->>'name', new.email),
    new.email,
    array['contributor'],
    'user'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Helper functions for RLS (SRS 0650/0660/0670: only valid, non-deactivated users act)
-- ---------------------------------------------------------------------------
create or replace function public.is_active_user()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.status = 'active'
  );
$$;

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.account_type = 'admin' and p.status = 'active'
  );
$$;

create or replace function public.has_role(target_role text)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.status = 'active' and target_role = any (p.roles)
  );
$$;

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.campaigns enable row level security;
alter table public.campaign_content enable row level security;
alter table public.external_service_accounts enable row level security;

-- profiles: a user can read/update their own row; admins can read/update/delete any row.
create policy profiles_select_own_or_admin on public.profiles
  for select using (id = auth.uid() or public.is_admin());

create policy profiles_update_own_or_admin on public.profiles
  for update using (id = auth.uid() or public.is_admin());

create policy profiles_delete_admin_only on public.profiles
  for delete using (public.is_admin());

-- campaigns: any active user can view; owner or admin can insert/update/delete.
create policy campaigns_select_active_users on public.campaigns
  for select using (public.is_active_user());

create policy campaigns_insert_active_users on public.campaigns
  for insert with check (public.is_active_user() and owner_id = auth.uid());

create policy campaigns_update_owner_or_admin on public.campaigns
  for update using (owner_id = auth.uid() or public.is_admin());

create policy campaigns_delete_owner_or_admin on public.campaigns
  for delete using (owner_id = auth.uid() or public.is_admin());

-- campaign_content:
--  - any active user can view content of a visible campaign
--  - contributors (or the campaign owner) can create/edit draft content they authored
--  - approvers can move pending_approval -> approved/rejected
--  - publishers can move approved -> scheduled/published
--  - admins can do anything
create policy campaign_content_select_active_users on public.campaign_content
  for select using (public.is_active_user());

create policy campaign_content_insert_contributor on public.campaign_content
  for insert with check (
    public.is_active_user()
    and created_by = auth.uid()
    and (public.has_role('contributor') or public.is_admin())
  );

-- Note: UPDATE policies without an explicit WITH CHECK reuse USING to validate the
-- resulting row too. Restricting USING to status in ('draft', 'rejected') would then
-- also block the update that moves a row *out* of that status (e.g. Contributor
-- submitting for approval), because the new row no longer satisfies it. WITH CHECK is
-- given separately so the old-row precondition doesn't also apply to the new row.
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

create policy campaign_content_delete_owner_or_admin on public.campaign_content
  for delete using (created_by = auth.uid() or public.is_admin());

-- external_service_accounts: strictly owned by the user; admins can view all.
create policy external_accounts_select_own_or_admin on public.external_service_accounts
  for select using (user_id = auth.uid() or public.is_admin());

create policy external_accounts_insert_own on public.external_service_accounts
  for insert with check (user_id = auth.uid() and public.is_active_user());

create policy external_accounts_update_own_or_admin on public.external_service_accounts
  for update using (user_id = auth.uid() or public.is_admin());

create policy external_accounts_delete_own_or_admin on public.external_service_accounts
  for delete using (user_id = auth.uid() or public.is_admin());
