postgres-# -- Clean up existing tables if you are re-running the lab
DROP TABLE IF EXISTS registrations CASCADE;
DROP TABLE IF EXISTS events CASCADE;
DROP TABLE IF EXISTS users CASCADE;
DROP TYPE IF EXISTS event_category;

-- Create an ENUM for event types
CREATE TYPE event_category AS ENUM ('concert', 'game');

-- 1. Users Table
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    full_name VARCHAR(150) NOT NULL,
    email VARCHAR(150) UNIQUE NOT NULL,
    signup_date DATE NOT NULL
);

-- 2. Events Table
CREATE TABLE events (
    event_id SERIAL PRIMARY KEY,
    title VARCHAR(150) NOT NULL,
    category event_category NOT NULL,
    event_date TIMESTAMP NOT NULL,
    capacity INT NOT NULL
);

-- 3. Registrations Table
CREATE TABLE registrations (
    registration_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id) ON DELETE CASCADE,
    event_id INT REFERENCES events(event_id) ON DELETE CASCADE,
    registration_date TIMESTAMP NOT NULL,
    status VARCHAR(20) DEFAULT 'confirmed'
);

-- Essential DBA Step: Indexing foreign keys for performance
CREATE INDEX idx_registrations_user_id ON registrations(user_id);
CREATE INDEX idx_registrations_event_id ON registrations(event_id);
CREATE INDEX idx_events_category ON events(category);
ERROR:  syntax error at or near "Q"
LINE 1: Q
        ^
NOTICE:  table "events" does not exist, skipping
DROP TABLE
NOTICE:  drop cascades to 3 other objects
DETAIL:  drop cascades to constraint portfolios_user_id_fkey on table portfolios
drop cascades to constraint orders_user_id_fkey on table orders
drop cascades to constraint accounts_user_id_fkey on table accounts
DROP TABLE
NOTICE:  type "event_category" does not exist, skipping
DROP TYPE
CREATE TYPE
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE INDEX
CREATE INDEX
CREATE INDEX
postgres=# -- 1. Insert 1 Million Users
-- Generates user names like "Attendee 4521" and random past signup dates
INSERT INTO users (full_name, email, signup_date)
SELECT
    'Attendee ' || seq,
    'user_' || seq || '_' || floor(random() * 1000)::text || '@example.com',
    CURRENT_DATE - (random() * 365 * 5)::int -- Random date within the last 5 years
FROM generate_series(1, 1000000) AS seq;

-- 2. Insert 1 Million Events
-- Randomly assigns 'concert' or 'game', random future dates, and random capacities
INSERT INTO events (title, category, event_date, capacity)
SELECT
    CASE WHEN random() > 0.5 THEN 'Concert Tour ' ELSE 'Championship Game ' END || seq,
    CASE WHEN random() > 0.5 THEN 'concert'::event_category ELSE 'game'::event_category END,
    CURRENT_TIMESTAMP + (random() * 365 || ' days')::interval, -- Random date next year
    floor(random() * 50000 + 100)::int -- Capacity between 100 and 50000
FROM generate_series(1, 1000000) AS seq;

-- 3. Insert 1 Million Registrations
-- Connects random users to random events, mostly 'confirmed' with some 'cancelled'
INSERT INTO registrations (user_id, event_id, registration_date, status)
SELECT
    floor(random() * 1000000 + 1)::int, -- Random user_id (1 to 1M)
    floor(random() * 1000000 + 1)::int, -- Random event_id (1 to 1M)
    CURRENT_TIMESTAMP - (random() * 30 || ' days')::interval,
    CASE WHEN random() > 0.15 THEN 'confirmed' ELSE 'cancelled' END
FROM generate_series(1, 1000000) AS seq;

-- DBA Step: Update table statistics for the query planner
ANALYZE users;
ANALYZE events;
ANALYZE registrations;
INSERT 0 1000000
INSERT 0 1000000
ERROR:  invalid input syntax for type interval: "6.546864997458712e-05 days"
ANALYZE
ANALYZE
ANALYZE
postgres=#
postgres=# WITH EventCounts AS (
    SELECT
        e.event_id,
        e.title,
        e.category,
        COUNT(r.registration_id) AS total_registrations
    FROM events e
    JOIN registrations r ON e.event_id = r.event_id
    WHERE r.status = 'confirmed'
    GROUP BY e.event_id, e.title, e.category
),
RankedEvents AS (
    SELECT
        title,
        category,
        total_registrations,
        DENSE_RANK() OVER (PARTITION BY category ORDER BY total_registrations DESC) as popularity_rank
    FROM EventCounts
)
SELECT * FROM RankedEvents
WHERE popularity_rank <= 5
ORDER BY category, popularity_rank;
 title | category | total_registrations | popularity_rank
-------+----------+---------------------+-----------------
(0 rows)

postgres=# WITH UserEventStats AS (
    SELECT
        u.user_id,
        u.full_name,
        COUNT(r.registration_id) FILTER (WHERE e.category = 'concert') AS concert_count,
        COUNT(r.registration_id) FILTER (WHERE e.category = 'game') AS game_count,
        COUNT(r.registration_id) AS total_events
    FROM users u
    JOIN registrations r ON u.user_id = r.user_id
    JOIN events e ON r.event_id = e.event_id
    WHERE r.status = 'confirmed'
    GROUP BY u.user_id, u.full_name
)
SELECT
    full_name,
    concert_count,
    game_count,
    total_events
FROM UserEventStats
WHERE concert_count > 0 AND game_count > 0
ORDER BY total_events DESC
LIMIT 20;
 full_name | concert_count | game_count | total_events
-----------+---------------+------------+--------------
(0 rows)

postgres=# -- 3. Insert 1 Million Registrations (FIXED)
INSERT INTO registrations (user_id, event_id, registration_date, status)
SELECT
    floor(random() * 1000000 + 1)::int,
    floor(random() * 1000000 + 1)::int,
    CURRENT_TIMESTAMP - (random() * interval '30 days'), -- Fixed line
    CASE WHEN random() > 0.15 THEN 'confirmed' ELSE 'cancelled' END
FROM generate_series(1, 1000000) AS seq;

-- Re-run analyze just to be safe
ANALYZE registrations;
INSERT 0 1000000
ANALYZE
postgres=# WITH UserEventStats AS (
    SELECT
        u.user_id,
        u.full_name,
        COUNT(r.registration_id) FILTER (WHERE e.category = 'concert') AS concert_count,
        COUNT(r.registration_id) FILTER (WHERE e.category = 'game') AS game_count,
        COUNT(r.registration_id) AS total_events
    FROM users u
    JOIN registrations r ON u.user_id = r.user_id
    JOIN events e ON r.event_id = e.event_id
    WHERE r.status = 'confirmed'
    GROUP BY u.user_id, u.full_name
)
SELECT
    full_name,
    concert_count,
    game_count,
    total_events
FROM UserEventStats
WHERE concert_count > 0 AND game_count > 0
ORDER BY total_events DESC
LIMIT 20;
    full_name    | concert_count | game_count | total_events
-----------------+---------------+------------+--------------
 Attendee 146828 |             3 |          5 |            8
 Attendee 684984 |             6 |          2 |            8
 Attendee 151554 |             1 |          7 |            8
 Attendee 640218 |             4 |          4 |            8
 Attendee 625180 |             3 |          4 |            7
 Attendee 12700  |             5 |          2 |            7
 Attendee 652066 |             5 |          2 |            7
 Attendee 348928 |             3 |          4 |            7
 Attendee 417046 |             2 |          5 |            7
 Attendee 393747 |             5 |          2 |            7
 Attendee 600588 |             4 |          3 |            7
 Attendee 620475 |             2 |          5 |            7
 Attendee 229659 |             3 |          4 |            7
 Attendee 627044 |             3 |          4 |            7
 Attendee 102938 |             2 |          5 |            7
 Attendee 235398 |             4 |          3 |            7
 Attendee 154144 |             4 |          3 |            7
 Attendee 188700 |             5 |          2 |            7
 Attendee 341965 |             2 |          5 |            7
 Attendee 462702 |             6 |          1 |            7
(20 rows)

postgres=# ^C
postgres=#


 EXPLAIN ANALYZE SELECT
    u.full_name,
    u.email,
    e.title,
    e.event_date,
    r.registration_date,
    -- The Correlated Subquery (will now actually execute)
    (
        SELECT COUNT(*)
        FROM registrations r2
        JOIN events e2 ON r2.event_id = e2.event_id
        WHERE r2.user_id = u.user_id
          AND e2.category = e.category
          AND r2.registration_id != r.registration_id
          AND EXTRACT(MONTH FROM r2.registration_date) = EXTRACT(MONTH FROM r.registration_date)
    ) AS similar_monthly_registrations
FROM users u
JOIN registrations r ON u.user_id = r.user_id
JOIN events e ON r.event_id = e.event_id
WHERE
    -- 1. Non-SARGable Date Math
    EXTRACT(ISODOW FROM r.registration_date) = EXTRACT(ISODOW FROM e.event_date)

    -- 2. Non-SARGable Date Differences
    AND (r.registration_date::date - u.signup_date::date) > 100

    -- 3. The FIXED String Match (Checks if the last digit of user_id is in the event title)
    AND e.title ILIKE '%' || RIGHT(u.user_id::text, 1) || '%'
ORDER BY
    -- 4. Sorting by the computed subquery
    similar_monthly_registrations DESC,
    e.event_date DESC
LIMIT 50;
                                                                                    QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=69582.83..69582.87 rows=17 width=88) (actual time=3138.449..3145.002 rows=50 loops=1)
   ->  Sort  (cost=69582.83..69582.87 rows=17 width=88) (actual time=3138.446..3144.984 rows=50 loops=1)
         Sort Key: ((SubPlan 1)) DESC, e.event_date DESC
         Sort Method: top-N heapsort  Memory: 36kB
         ->  Gather  (cost=24463.10..69582.48 rows=17 width=88) (actual time=365.434..3124.497 rows=123892 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               ->  Nested Loop  (cost=23463.10..68156.38 rows=7 width=92) (actual time=338.954..1157.408 rows=41297 loops=3)
                     Join Filter: ((e.title)::text ~~* (('%'::text || "right"((u.user_id)::text, 1)) || '%'::text))
                     Rows Removed by Join Filter: 47914
                     ->  Parallel Hash Join  (cost=23462.67..66068.34 rows=4167 width=50) (actual time=338.821..551.471 rows=95314 loops=3)
                           Hash Cond: ((r.event_id = e.event_id) AND (EXTRACT(isodow FROM r.registration_date) = EXTRACT(isodow FROM e.event_date)))
                           ->  Parallel Seq Scan on registrations r  (cost=0.00..25000.33 rows=833333 width=20) (actual time=0.016..58.968 rows=666667 loops=3)
                           ->  Parallel Hash  (cost=13956.67..13956.67 rows=416667 width=38) (actual time=125.224..125.225 rows=333333 loops=3)
                                 Buckets: 131072  Batches: 16  Memory Usage: 5696kB
                                 ->  Parallel Seq Scan on events e  (cost=0.00..13956.67 rows=416667 width=38) (actual time=0.032..36.002 rows=333333 loops=3)
                     ->  Index Scan using users_pkey on users u  (cost=0.42..0.48 rows=1 width=50) (actual time=0.006..0.006 rows=1 loops=285943)
                           Index Cond: (user_id = r.user_id)
                           Filter: (((r.registration_date)::date - signup_date) > 100)
                           Rows Removed by Filter: 0
               SubPlan 1
                 ->  Aggregate  (cost=24.96..24.97 rows=1 width=8) (actual time=0.022..0.022 rows=1 loops=123892)
                       ->  Nested Loop  (cost=0.85..24.95 rows=1 width=0) (actual time=0.017..0.022 rows=1 loops=123892)
                             ->  Index Scan using idx_registrations_user_id on registrations r2  (cost=0.43..16.51 rows=1 width=4) (actual time=0.009..0.013 rows=1 loops=123892)
                                   Index Cond: (user_id = u.user_id)
                                   Filter: ((registration_id <> r.registration_id) AND (EXTRACT(month FROM registration_date) = EXTRACT(month FROM r.registration_date)))
                                   Rows Removed by Filter: 2
                             ->  Index Scan using events_pkey on events e2  (cost=0.42..8.45 rows=1 width=4) (actual time=0.006..0.006 rows=0 loops=156566)
                                   Index Cond: (event_id = r2.event_id)
                                   Filter: (category = e.category)
                                   Rows Removed by Filter: 1
 Planning Time: 2.148 ms
 Execution Time: 3145.223 ms
(33 rows)