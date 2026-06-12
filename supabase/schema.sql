-- ERIOR WORLD — ejecuta en Supabase → SQL Editor
-- Crea tablas, políticas RLS y triggers de aprobación PayPal

-- Perfil de jugador (1 por cuenta auth)
create table if not exists public.player_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  avatar int not null default 0,
  level int not null default 0,
  xp int not null default 0,
  crystals int not null default 0,
  gold int not null default 0,
  audios_purchased int not null default 0,
  tools text[] not null default '{}',
  audio_unlocks text[] not null default '{}',
  active_skin text not null default 'default',
  skins text[] not null default '{}',
  premium_skins text[] not null default '{}',
  col double precision not null default 44,
  row double precision not null default 44,
  tier_notified text[] not null default '{}',
  builds jsonb not null default '[]'::jsonb,
  quests_done text[] not null default '{}',
  build_count int not null default 0,
  stats jsonb not null default '{"shopVisits":0,"crystalsTotal":0,"aliciaVisits":0}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Compras de skins vía PayPal (Pauline aprueba en dashboard)
create table if not exists public.skin_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  skin_id text not null,
  amount_mxn numeric(10,2) not null,
  paypal_txn text,
  payer_email text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  notes text,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

create index if not exists idx_skin_purchases_user on public.skin_purchases(user_id);
create index if not exists idx_skin_purchases_status on public.skin_purchases(status);

-- Compras de audios (Pauline aprueba → audios_purchased + desbloqueos)
create table if not exists public.audio_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  audio_name text not null,
  amount_mxn numeric(10,2) not null default 1190,
  paypal_txn text,
  payer_email text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  notes text,
  created_at timestamptz not null default now(),
  approved_at timestamptz
);

create index if not exists idx_audio_purchases_user on public.audio_purchases(user_id);
create index if not exists idx_audio_purchases_status on public.audio_purchases(status);

-- Parcelas / mundos visitables (fase futura: pagar para entrar y chatear)
create table if not exists public.world_parcels (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'Mi Mundo',
  col int not null,
  row int not null,
  radius int not null default 6,
  visit_price_mxn numeric(10,2) not null default 49,
  builds jsonb not null default '[]'::jsonb,
  is_public boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists idx_world_parcels_owner on public.world_parcels(owner_id);

-- Al aprobar compra skin → desbloquea en cuenta
create or replace function public.handle_skin_purchase_approval()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and (old.status is distinct from 'approved') then
    update public.player_profiles
    set premium_skins = case
      when new.skin_id = any(premium_skins) then premium_skins
      else array_append(premium_skins, new.skin_id)
    end,
    updated_at = now()
    where id = new.user_id;
    new.approved_at = coalesce(new.approved_at, now());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_skin_purchase_approval on public.skin_purchases;
create trigger trg_skin_purchase_approval
  before update on public.skin_purchases
  for each row execute function public.handle_skin_purchase_approval();

-- Al aprobar compra audio → cuenta + hacha (3+) + skin dorada (5+)
create or replace function public.handle_audio_purchase_approval()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status = 'approved' and (old.status is distinct from 'approved') then
    update public.player_profiles
    set audios_purchased = audios_purchased + 1, updated_at = now()
    where id = new.user_id;
    update public.player_profiles
    set tools = case when 'axe' = any(tools) then tools else array_append(tools, 'axe') end
    where id = new.user_id and audios_purchased >= 3;
    update public.player_profiles
    set premium_skins = case
      when 'dorada' = any(premium_skins) then premium_skins
      else array_append(premium_skins, 'dorada')
    end
    where id = new.user_id and audios_purchased >= 5;
    new.approved_at = coalesce(new.approved_at, now());
  end if;
  return new;
end;
$$;

drop trigger if exists trg_audio_purchase_approval on public.audio_purchases;
create trigger trg_audio_purchase_approval
  before update on public.audio_purchases
  for each row execute function public.handle_audio_purchase_approval();

-- Auto-crear perfil al registrarse
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.player_profiles (id, username)
  values (new.id, 'viajero_' || substr(replace(new.id::text, '-', ''), 1, 8))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- RLS
alter table public.player_profiles enable row level security;
alter table public.skin_purchases enable row level security;
alter table public.audio_purchases enable row level security;
alter table public.world_parcels enable row level security;

drop policy if exists "profiles_select_own" on public.player_profiles;
create policy "profiles_select_own" on public.player_profiles
  for select using (auth.uid() = id);

drop policy if exists "profiles_insert_own" on public.player_profiles;
create policy "profiles_insert_own" on public.player_profiles
  for insert with check (auth.uid() = id);

drop policy if exists "profiles_update_own" on public.player_profiles;
create policy "profiles_update_own" on public.player_profiles
  for update using (auth.uid() = id);

drop policy if exists "purchases_select_own" on public.skin_purchases;
create policy "purchases_select_own" on public.skin_purchases
  for select using (auth.uid() = user_id);

drop policy if exists "purchases_insert_own" on public.skin_purchases;
create policy "purchases_insert_own" on public.skin_purchases
  for insert with check (auth.uid() = user_id);

drop policy if exists "audio_purchases_select_own" on public.audio_purchases;
create policy "audio_purchases_select_own" on public.audio_purchases
  for select using (auth.uid() = user_id);

drop policy if exists "audio_purchases_insert_own" on public.audio_purchases;
create policy "audio_purchases_insert_own" on public.audio_purchases
  for insert with check (auth.uid() = user_id);

drop policy if exists "parcels_select_public" on public.world_parcels;
create policy "parcels_select_public" on public.world_parcels
  for select using (is_public = true or auth.uid() = owner_id);

drop policy if exists "parcels_insert_own" on public.world_parcels;
create policy "parcels_insert_own" on public.world_parcels
  for insert with check (auth.uid() = owner_id);

drop policy if exists "parcels_update_own" on public.world_parcels;
create policy "parcels_update_own" on public.world_parcels
  for update using (auth.uid() = owner_id);

-- Migración si ya tenías player_profiles sin columnas v6:
-- alter table public.player_profiles add column if not exists gold int not null default 0;
-- alter table public.player_profiles add column if not exists audios_purchased int not null default 0;
-- alter table public.player_profiles add column if not exists tools text[] not null default '{}';
-- alter table public.player_profiles add column if not exists audio_unlocks text[] not null default '{}';
-- alter table public.player_profiles add column if not exists inventory jsonb not null default '[]'::jsonb;
-- alter table public.player_profiles add column if not exists guide_done boolean not null default false;
-- alter table public.player_profiles add column if not exists hp int not null default 100;
-- alter table public.player_profiles add column if not exists max_hp int not null default 100;
-- alter table public.player_profiles add column if not exists wood int not null default 0;

-- Pauline aprueba:
-- update public.skin_purchases set status = 'approved' where id = 'UUID';
-- update public.audio_purchases set status = 'approved' where id = 'UUID';
