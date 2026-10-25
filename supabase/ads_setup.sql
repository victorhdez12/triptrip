-- ADS_SETUP.sql
-- Ejecutar en el SQL Editor de Supabase ANTES de probar los anuncios.
--
--   1. Tabla ad_impressions — registro de cada impresión (AdService.logImpression)
--   2. RLS: cualquier usuario autenticado inserta SUS impresiones; nadie lee
--      directamente la tabla (solo vía RPC).
--   3. RPC get_ad_impression_stats — agregados para el dashboard interno.

-- ── 1. TABLA ─────────────────────────────────────────────────
create table if not exists public.ad_impressions (
  id            uuid primary key default gen_random_uuid(),
  firebase_uid  text,                          -- puede ser null (usuario anónimo)
  ad_type       text not null,                 -- 'banner' | 'native_feed'
  placement     text not null,                 -- p.ej. 'dashboard_feed'
  platform      text,                          -- 'android' | 'ios'
  created_at    timestamptz not null default now()
);

create index if not exists ad_impressions_created_at_idx
  on public.ad_impressions (created_at desc);
create index if not exists ad_impressions_placement_idx
  on public.ad_impressions (placement);

-- ── 2. RLS ───────────────────────────────────────────────────
alter table public.ad_impressions enable row level security;

-- Insertar: cualquiera con la anon key (la app). No exigimos match de uid
-- porque la app usa Firebase Auth (no Supabase Auth) y el patrón del
-- proyecto es confiar en firebase_uid enviado por el cliente.
drop policy if exists ad_impressions_insert on public.ad_impressions;
create policy ad_impressions_insert
  on public.ad_impressions for insert
  with check (true);

-- Leer: NADIE directamente (sin policy de select).
-- Las lecturas van solo por la RPC security definer de abajo.

-- ── 3. RPC DE ESTADÍSTICAS ───────────────────────────────────
-- Agregados por día / tipo / placement de los últimos `days_back` días.
create or replace function public.get_ad_impression_stats(days_back int default 30)
returns table (
  day         date,
  ad_type     text,
  placement   text,
  impressions bigint
)
language sql
security definer
set search_path = public
as $$
  select
    created_at::date as day,
    ad_type,
    placement,
    count(*) as impressions
  from public.ad_impressions
  where created_at >= now() - make_interval(days => days_back)
  group by 1, 2, 3
  order by 1 desc, 4 desc;
$$;

grant execute on function public.get_ad_impression_stats(int) to anon, authenticated;
