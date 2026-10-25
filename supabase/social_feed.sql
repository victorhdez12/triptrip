-- ══════════════════════════════════════════════════════════════
-- TripTrip · feed social agregado (nombres de tabla corregidos
-- para el esquema real del proyecto)
--
-- IMPORTANTE: la auth es Firebase, no Supabase Auth.
-- Todo se indexa por firebase_uid (text). No uses auth.uid() ni
-- referencias a auth.users: con Firebase, auth.uid() es siempre NULL
-- desde el cliente y cualquier política basada en él bloquea todo.
--
-- Correcciones respecto al original de Downloads:
--   · No crea una tabla `follows` nueva: el proyecto ya tiene
--     `user_follows` (follower_uid, following_uid), usada por
--     SocialService. Se reutiliza tal cual.
--   · El JOIN de nombres de usuario usa `users`, no `profiles`
--     (tabla real usada por SocialService/ItineraryService).
-- ══════════════════════════════════════════════════════════════

-- ── 1. Guardar dentro de un viaje concreto ────────────────────
-- Un favorito sin destino es una lista muerta. Con trip_id, guardar
-- desde Explorar llena directamente el viaje que se ve en Home.
alter table place_favorites
  add column if not exists trip_id uuid;

create index if not exists place_favorites_trip_idx
  on place_favorites (trip_id);

-- ── 2. Likes (reacción ligera, distinta de favorito y de rating) ──
create table if not exists place_likes (
  firebase_uid text not null,
  place_id     text not null references places(id) on delete cascade,
  created_at   timestamptz not null default now(),
  primary key (firebase_uid, place_id)
);
create index if not exists place_likes_place_idx on place_likes (place_id);

-- Aplica a place_likes la MISMA política de RLS que tenga
-- place_favorites (probablemente RLS desactivado o política
-- permisiva, porque la identidad la valida Firebase, no Postgres).

-- Contador denormalizado, igual que los otros de `places`
alter table places add column if not exists likes_count int not null default 0;

create or replace function bump_place_likes() returns trigger
language plpgsql as $$
begin
  if tg_op = 'INSERT' then
    update places set likes_count = likes_count + 1 where id = new.place_id;
  elsif tg_op = 'DELETE' then
    update places set likes_count = greatest(likes_count - 1, 0) where id = old.place_id;
  end if;
  return null;
end $$;

drop trigger if exists place_likes_count on place_likes;
create trigger place_likes_count
  after insert or delete on place_likes
  for each row execute function bump_place_likes();

-- ── 3. Follows ────────────────────────────────────────────────
-- El proyecto YA tiene `user_follows` (follower_uid, following_uid),
-- usada por SocialService.follow/unfollow. No se crea tabla nueva.

-- ══════════════════════════════════════════════════════════════
-- 4. FEED AGREGADO
--
-- Verbos agregables (save, like): se agrupan por (verbo, sitio, día)
--   → cinco amigos guardando lo mismo = UNA fila con actor_count = 5.
-- Contenido original (publish, comment): nunca se agrupa, una fila
--   por evento.
--
-- Usa `users` (firebase_uid, display_name) para los nombres.
-- ══════════════════════════════════════════════════════════════
create or replace function feed_for_user(
  p_uid    text,
  p_limit  int default 20,
  p_offset int default 0
)
returns table (
  group_key       text,
  verb            text,
  place_id        text,
  place_name      text,
  location        text,
  category        text,
  country_flag    text,
  actor_names     text[],
  actor_count     int,
  likes_count     int,
  comments_count  int,
  favorites_count int,
  liked_by_me     boolean,
  saved_by_me     boolean,
  last_at         timestamptz
)
language sql stable as $$
  with followed as (
    select following_uid as uid from user_follows where follower_uid = p_uid
  ),
  ev as (
    select f.firebase_uid as actor_uid, 'save'::text as verb,
           f.place_id::text as place_id, f.created_at
      from place_favorites f
      join followed fo on fo.uid = f.firebase_uid
    union all
    select l.firebase_uid, 'like', l.place_id::text, l.created_at
      from place_likes l
      join followed fo on fo.uid = l.firebase_uid
    union all
    select c.firebase_uid, 'comment', c.place_id::text, c.created_at
      from place_comments c
      join followed fo on fo.uid = c.firebase_uid
    union all
    select v.user_uid, 'publish', v.place_id::text, v.created_at
      from place_visits v
      join followed fo on fo.uid = v.user_uid
  ),
  recent as (
    select * from ev where created_at > now() - interval '30 days'
  ),
  grouped as (
    select
      case when r.verb in ('save','like')
        then r.verb || ':' || r.place_id || ':'
             || to_char(date_trunc('day', r.created_at), 'YYYYMMDD')
        else r.verb || ':' || r.place_id || ':' || r.actor_uid || ':'
             || to_char(r.created_at, 'YYYYMMDDHH24MISS')
      end                                                     as group_key,
      r.verb,
      r.place_id,
      max(r.created_at)                                       as last_at,
      count(distinct r.actor_uid)::int                        as actor_count,
      (array_agg(coalesce(u.display_name, 'Viajero')
        order by r.created_at desc))[1:3]                     as actor_names
    from recent r
    left join users u on u.firebase_uid = r.actor_uid
    group by 1, 2, 3
  )
  select
    g.group_key, g.verb, g.place_id,
    p.name,
    coalesce(p.location, ''),
    coalesce(p.category, ''),
    coalesce(p.country_flag, '📍'),
    g.actor_names,
    g.actor_count,
    coalesce(p.likes_count, 0),
    coalesce(p.comments_count, 0),
    coalesce(p.favorites_count, 0),
    exists (select 1 from place_likes pl
              where pl.place_id = g.place_id and pl.firebase_uid = p_uid),
    exists (select 1 from place_favorites pf
              where pf.place_id = g.place_id and pf.firebase_uid = p_uid),
    g.last_at
  from grouped g
  join places p on p.id::text = g.place_id
  -- Lo que varias personas han hecho pesa más que lo más reciente
  order by (g.actor_count > 1) desc, g.last_at desc
  limit p_limit offset p_offset;
$$;

-- ══════════════════════════════════════════════════════════════
-- 5. VIAJEROS EN TUS MISMAS FECHAS (opcional — necesita tu esquema
--    real de viajes: trips / trip_members). Descomenta y ajusta
--    si quieres activarlo.
-- ══════════════════════════════════════════════════════════════
-- create or replace function travelers_matching_trip(
--   p_uid text, p_trip uuid, p_limit int default 6
-- ) returns table (firebase_uid text, display_name text, trip_title text)
-- language sql stable as $$
--   with mine as (select * from trips where id = p_trip)
--   select distinct on (u.firebase_uid)
--          u.firebase_uid, u.display_name, t.title
--   from trips t
--   join mine m on t.destination = m.destination
--                and t.start_date <= m.end_date
--                and t.end_date   >= m.start_date
--                and t.id <> m.id
--   join trip_members tm on tm.trip_id = t.id
--   join users u on u.firebase_uid = tm.firebase_uid
--   where u.firebase_uid <> p_uid
--   limit p_limit;
-- $$;
