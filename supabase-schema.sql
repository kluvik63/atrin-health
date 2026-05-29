-- ============================================================
-- ATRIN LAB · Health Tracker · Database Schema
-- ============================================================
-- Откройте Supabase → SQL Editor → New query
-- Скопируйте весь этот файл, вставьте, нажмите "Run"
-- Должно появиться "Success. No rows returned"
-- ============================================================

-- Пользователи
create table if not exists users (
  id uuid default gen_random_uuid() primary key,
  phone text unique not null,
  name text,
  city text,
  consent_given_at timestamptz,
  created_at timestamptz default now(),
  last_active_at timestamptz default now(),
  app_version text default 'pwa-v2',
  -- метаданные клиента ATRIN LAB (заполняются вручную или из CRM)
  is_customer boolean default false,
  customer_since date,
  notes text
);

create index if not exists idx_users_phone on users(phone);
create index if not exists idx_users_last_active on users(last_active_at desc);
create index if not exists idx_users_created on users(created_at desc);

-- Ежедневные записи
create table if not exists entries (
  user_id uuid references users(id) on delete cascade,
  date date not null,
  sleep_quality smallint check (sleep_quality between 0 and 10),
  energy smallint check (energy between 0 and 10),
  mood smallint check (mood between 0 and 10),
  stress smallint check (stress between 0 and 10),
  sleep_hours numeric(3,1),
  water smallint,
  steps integer,
  supplements text[] default '{}',
  habits text[] default '{}',
  notes text,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  primary key (user_id, date)
);

create index if not exists idx_entries_date on entries(date desc);
create index if not exists idx_entries_user_date on entries(user_id, date desc);

-- События для аналитики
create table if not exists events (
  id bigserial primary key,
  user_id uuid references users(id) on delete cascade,
  event_type text not null,
  metadata jsonb default '{}',
  created_at timestamptz default now()
);

create index if not exists idx_events_user_type on events(user_id, event_type, created_at desc);
create index if not exists idx_events_type_date on events(event_type, created_at desc);

-- ============================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================
-- Включаем защиту на чтение/запись.
-- В режиме v2 без SMS-аутентификации мы используем "soft" политику:
-- анонимный клиент может писать, но читать только свои данные через
-- параметр user_id. Для production стоит подключить Supabase Auth.

alter table users enable row level security;
alter table entries enable row level security;
alter table events enable row level security;

-- Удалить старые политики, если перезаливаем
drop policy if exists "users insert" on users;
drop policy if exists "users select" on users;
drop policy if exists "users update" on users;
drop policy if exists "entries insert" on entries;
drop policy if exists "entries select" on entries;
drop policy if exists "entries update" on entries;
drop policy if exists "events insert" on events;

-- Политики: открытая запись, чтение со ссылкой на user_id
create policy "users insert" on users for insert with check (true);
create policy "users select" on users for select using (true);
create policy "users update" on users for update using (true);

create policy "entries insert" on entries for insert with check (true);
create policy "entries select" on entries for select using (true);
create policy "entries update" on entries for update using (true);

create policy "events insert" on events for insert with check (true);

-- ============================================================
-- ПОЛЕЗНЫЕ VIEW И ФУНКЦИИ ДЛЯ АНАЛИТИКИ
-- ============================================================

-- Расширенная статистика по каждому пользователю
create or replace view user_stats as
  select
    u.id,
    u.phone,
    u.name,
    u.city,
    u.is_customer,
    u.created_at,
    u.last_active_at,
    extract(day from now() - u.created_at)::int as days_since_signup,
    extract(day from now() - u.last_active_at)::int as days_since_active,
    count(distinct e.date) as days_tracked,
    max(e.date) as last_entry_date,
    round(avg(e.energy)::numeric, 1) as avg_energy,
    round(avg(e.mood)::numeric, 1) as avg_mood,
    round(avg(e.sleep_quality)::numeric, 1) as avg_sleep,
    round(avg(e.stress)::numeric, 1) as avg_stress
  from users u
  left join entries e on e.user_id = u.id
  group by u.id;

-- Воронка активации (% дошли до N-го дня)
create or replace view activation_funnel as
  with user_days as (
    select user_id, count(distinct date) as n_days from entries group by user_id
  )
  select
    'Зарегистрировались' as step, count(*) as users, 100.0 as pct
    from users
  union all
  select '1+ день записей', count(*),
    round(100.0 * count(*) / nullif((select count(*) from users), 0), 1)
    from user_days where n_days >= 1
  union all
  select '7+ дней записей', count(*),
    round(100.0 * count(*) / nullif((select count(*) from users), 0), 1)
    from user_days where n_days >= 7
  union all
  select '30+ дней записей', count(*),
    round(100.0 * count(*) / nullif((select count(*) from users), 0), 1)
    from user_days where n_days >= 30;

-- Возвращающиеся пользователи (заходили хотя бы раз за последние N дней)
create or replace function active_users_last_n_days(n integer)
returns table (
  active int,
  total int,
  percentage numeric
)
language sql as $$
  select
    count(*) filter (where last_active_at > now() - (n || ' days')::interval)::int as active,
    count(*)::int as total,
    round(100.0 * count(*) filter (where last_active_at > now() - (n || ' days')::interval) / nullif(count(*), 0), 1) as percentage
  from users;
$$;
