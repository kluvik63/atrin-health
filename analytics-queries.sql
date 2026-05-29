-- ============================================================
-- ATRIN LAB · Готовые SQL-запросы для аналитики
-- ============================================================
-- Откройте Supabase → SQL Editor
-- Скопируйте нужный запрос, нажмите "Run"
-- Результат можно экспортировать в CSV
-- ============================================================


-- ──────────────────────────────────────────────────────────────
-- 1. ОБЩАЯ СТАТИСТИКА
-- ──────────────────────────────────────────────────────────────

-- Сколько всего пользователей и записей
select
  (select count(*) from users) as total_users,
  (select count(*) from entries) as total_entries,
  (select count(*) from users where last_active_at > now() - interval '7 days') as active_week,
  (select count(*) from users where last_active_at > now() - interval '30 days') as active_month;


-- Воронка активации (% дошли до N-го дня)
select * from activation_funnel;


-- Активные за разные периоды
select * from active_users_last_n_days(1);   -- сегодня
select * from active_users_last_n_days(7);   -- неделя
select * from active_users_last_n_days(30);  -- месяц


-- ──────────────────────────────────────────────────────────────
-- 2. РОСТ И НОВЫЕ ПОЛЬЗОВАТЕЛИ
-- ──────────────────────────────────────────────────────────────

-- Регистрации по дням за последний месяц
select
  date(created_at) as day,
  count(*) as new_users
from users
where created_at > now() - interval '30 days'
group by day
order by day desc;


-- Регистрации по неделям (для графика)
select
  to_char(date_trunc('week', created_at), 'YYYY-MM-DD') as week_start,
  count(*) as new_users
from users
group by week_start
order by week_start desc
limit 26;


-- ──────────────────────────────────────────────────────────────
-- 3. ВАШИ КЛИЕНТЫ
-- ──────────────────────────────────────────────────────────────

-- Список всех клиентов с контактами и активностью
select
  phone,
  name,
  city,
  to_char(created_at, 'DD.MM.YYYY') as registered,
  to_char(last_active_at, 'DD.MM.YYYY') as last_seen,
  days_tracked,
  round(avg_energy, 1) as avg_energy,
  round(avg_mood, 1) as avg_mood
from user_stats
order by created_at desc;


-- Самые активные пользователи (топ-20)
select
  name, phone, city,
  days_tracked,
  to_char(last_active_at, 'DD.MM.YYYY HH24:MI') as last_seen
from user_stats
order by days_tracked desc nulls last
limit 20;


-- Города ваших пользователей
select
  coalesce(nullif(city, ''), '(не указан)') as city,
  count(*) as users
from users
group by city
order by users desc;


-- "Спящие" клиенты — давно не заходили, есть смысл напомнить
select
  name, phone, city,
  to_char(last_active_at, 'DD.MM.YYYY') as last_seen,
  extract(day from now() - last_active_at)::int as days_inactive,
  days_tracked
from user_stats
where last_active_at < now() - interval '14 days'
  and days_tracked >= 3   -- те, кто реально пользовался
order by days_inactive asc
limit 50;


-- Новые пользователи за последнюю неделю — для приветствия / онбординга
select
  name, phone, city,
  to_char(created_at, 'DD.MM.YYYY HH24:MI') as registered
from users
where created_at > now() - interval '7 days'
order by created_at desc;


-- ──────────────────────────────────────────────────────────────
-- 4. ПОВЕДЕНИЕ И ЭНГЕЙДЖМЕНТ
-- ──────────────────────────────────────────────────────────────

-- Средние показатели по всей базе за последний месяц
select
  count(distinct user_id) as active_users,
  count(*) as entries,
  round(avg(sleep_quality)::numeric, 2) as avg_sleep,
  round(avg(energy)::numeric, 2) as avg_energy,
  round(avg(mood)::numeric, 2) as avg_mood,
  round(avg(stress)::numeric, 2) as avg_stress
from entries
where date > current_date - interval '30 days';


-- Записи по дням недели — когда люди чаще заполняют
select
  case extract(dow from date)
    when 0 then '7. Воскресенье'
    when 1 then '1. Понедельник'
    when 2 then '2. Вторник'
    when 3 then '3. Среда'
    when 4 then '4. Четверг'
    when 5 then '5. Пятница'
    when 6 then '6. Суббота'
  end as day_of_week,
  count(*) as entries
from entries
where date > current_date - interval '60 days'
group by day_of_week
order by day_of_week;


-- Какие добавки чаще всего отмечают
select
  unnest(supplements) as supplement,
  count(*) as times_taken,
  count(distinct user_id) as unique_users
from entries
where date > current_date - interval '30 days'
group by supplement
order by times_taken desc;


-- Какие привычки реально выполняют
select
  unnest(habits) as habit,
  count(*) as times_done,
  count(distinct user_id) as unique_users,
  round(100.0 * count(*) / nullif(count(distinct user_id), 0) / 30, 1) as avg_pct_of_month
from entries
where date > current_date - interval '30 days'
group by habit
order by times_done desc;


-- ──────────────────────────────────────────────────────────────
-- 5. КОГОРТНЫЙ АНАЛИЗ (для бизнес-отчётов)
-- ──────────────────────────────────────────────────────────────

-- Удержание: сколько % от регистрации зашли через 1/7/30 дней
with cohorts as (
  select
    date_trunc('week', created_at)::date as cohort,
    id,
    last_active_at
  from users
  where created_at < now() - interval '30 days'
)
select
  cohort,
  count(*) as registered,
  count(*) filter (where last_active_at > cohort + interval '1 day') as d1,
  count(*) filter (where last_active_at > cohort + interval '7 days') as d7,
  count(*) filter (where last_active_at > cohort + interval '30 days') as d30,
  round(100.0 * count(*) filter (where last_active_at > cohort + interval '7 days') / count(*), 1) as d7_pct,
  round(100.0 * count(*) filter (where last_active_at > cohort + interval '30 days') / count(*), 1) as d30_pct
from cohorts
group by cohort
order by cohort desc;


-- ──────────────────────────────────────────────────────────────
-- 6. РУЧНЫЕ ОПЕРАЦИИ
-- ──────────────────────────────────────────────────────────────

-- Отметить пользователя как клиента магазина (после покупки)
update users
set is_customer = true, customer_since = current_date
where phone = '+79991234567';


-- Найти пользователя по части номера
select * from users where phone like '%1234567%';


-- Удалить тестовый аккаунт
delete from users where phone = '+79991234567';
-- (записи удалятся автоматически по ON DELETE CASCADE)
