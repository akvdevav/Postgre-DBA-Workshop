### Workshop Lab: Simulating "Too Many Dead Tuples" in an Order Book

Prerequisites: Setup the High-Frequency Order Book
First, we will create our order_book table. To make this lab work quickly, we are going to do something you should never do in production: we are going to explicitly disable Autovacuum on this specific table to guarantee that dead tuples accumulate.

```
-- Enable our diagnostic extension
CREATE EXTENSION IF NOT EXISTS pgstattuple;
```

```
-- Create the order book table
CREATE TABLE order_book (
    order_id BIGSERIAL PRIMARY KEY,
    trader_id INT NOT NULL,
    symbol VARCHAR(10) NOT NULL,
    order_type VARCHAR(4) NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    status VARCHAR(15) NOT NULL,
    created_at TIMESTAMP DEFAULT NOW()
);
```

```
-- SABOTAGE: Disable autovacuum specifically for this table!
ALTER TABLE order_book SET (autovacuum_enabled = false);
```

```
-- Insert 100,000 initial "OPEN" orders
INSERT INTO order_book (trader_id, symbol, order_type, price, status)
SELECT 
    floor(random() * 1000 + 1)::INT,
    (ARRAY['AAPL', 'MSFT', 'AMZN', 'NVDA', 'TSLA'])[floor(random() * 5 + 1)],
    (ARRAY['BUY', 'SELL'])[floor(random() * 2 + 1)],
    (random() * 200 + 50)::NUMERIC(10, 2),
    'OPEN'
FROM generate_series(1, 100000);
```


#### Step 1: Baseline Query Performance
Before we generate the dead tuples, let's see how fast the database can find a specific subset of active orders. Notice the Execution Time.

```
-- Turn on timing in psql
\timing on
```

```
-- Query for open Apple buy orders
SELECT COUNT(*) FROM order_book 
WHERE symbol = 'AAPL' AND order_type = 'BUY' AND status = 'OPEN';
```

(Record the time—it should be a few milliseconds.)

#### Step 2: The HFT Churn (Generating Dead Tuples)
In a trading system, algorithms constantly adjust prices and cancel orders. Because we disabled Autovacuum, every single UPDATE and DELETE will leave a permanent dead tuple behind.
We will use a PL/pgSQL block to simulate a high-speed churn loop. This will update the prices of open orders and cancel a fraction of them repeatedly.

```
-- Simulate high-frequency churn
DO $$
BEGIN
    FOR i IN 1..20 LOOP
        -- Algorithms constantly adjusting their bid/ask prices by small fractions
        UPDATE order_book 
        SET price = price + (random() * 0.50 - 0.25) 
        WHERE status = 'OPEN';
        
        -- Cancelling a subset of orders
        UPDATE order_book 
        SET status = 'CANCELLED' 
        WHERE order_id % 20 = i;
    END LOOP;
END $$;
```

#### Step 3: Triggering the "Alert"
Now that our churn script has run, let's look at what your monitoring tools are seeing. Monitoring tools typically query system catalogs like pg_stat_user_tables to trigger alerts.
```
-- The view your monitoring tools use to trigger alerts
SELECT 
    relname AS table_name,
    n_live_tup AS live_tuples,
    n_dead_tup AS dead_tuples
FROM pg_stat_user_tables 
WHERE relname = 'order_book';
```

```
-- The physical reality on disk
SELECT * FROM pgstattuple('order_book');
```

Observe the results: You will see that dead_tuples vastly outnumber live_tuples. If you had an alert set to trigger at 10,000 dead tuples, it would be screaming right now.

#### Step 4: The Performance Impact
Now, run the exact same query we ran in Step 1.
```
-- Query for open Apple buy orders again
SELECT COUNT(*) FROM order_book 
WHERE symbol = 'AAPL' AND order_type = 'BUY' AND status = 'OPEN';

-- Turn timing off
\timing off
```

You will notice the execution time is significantly slower. Even though there are fewer 'OPEN' rows than when we started, PostgreSQL has to sequentially scan past hundreds of thousands of dead rows to find the live ones.

#### Step 5: The Fix
To resolve this, we need to undo our sabotage, re-enable Autovacuum, and manually vacuum the table to clear the immediate alert.
```
-- Re-enable autovacuum for the table
ALTER TABLE order_book SET (autovacuum_enabled = true);
```

```
-- Run a manual vacuum to clean up the dead tuples
VACUUM VERBOSE order_book;
```

```
-- Verify the dead tuples are gone
SELECT 
    relname AS table_name,
    n_dead_tup AS dead_tuples
FROM pg_stat_user_tables 
WHERE relname = 'order_book';
```


```
-- CUSTOM TUNING: Make autovacuum hyper-aggressive just for this table!
-- It will trigger after only 1,000 dead tuples accumulate instead of the default 20% + 50 rows.
ALTER TABLE order_book SET (
    autovacuum_enabled = true,
    autovacuum_vacuum_scale_factor = 0,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_vacuum_cost_delay = 0
);
```


```
-- Insert 100,000 initial "OPEN" orders
INSERT INTO order_book (trader_id, symbol, order_type, price, status)
SELECT 
    floor(random() * 1000 + 1)::INT,
    (ARRAY['AAPL', 'MSFT', 'AMZN', 'NVDA', 'TSLA'])[floor(random() * 5 + 1)],
    (ARRAY['BUY', 'SELL'])[floor(random() * 2 + 1)],
    (random() * 200 + 50)::NUMERIC(10, 2),
    'OPEN'
FROM generate_series(1, 100000);
```

#### Step 1: Open a Live Monitoring Session
Before generating the churn, open a second terminal window connected to your database. We will use this to catch autovacuum in the act.

Run this query in your second terminal. It utilizes watch (if using psql) to refresh every half-second and look for running autovacuum workers:

```
-- In Terminal 2: Watch for active autovacuum processes
 SELECT
    pid,
    phase,
    heap_blks_total,
    heap_blks_scanned
FROM pg_stat_progress_vacuum;
\watch 0.5
```
(If your client doesn't support \watch, you can manually spam-execute that SELECT query during Step 2).

###### Sample output
```
         Sat Jun  6 15:34:00 2026 (every 0.5s)

 pid |     phase     | heap_blks_total | heap_blks_scanned
-----+---------------+-----------------+-------------------
 485 | scanning heap |           29782 |              5488
(1 row)
```


#### Step 2: The HFT Churn (Generating Dead Tuples)
Now, return to Terminal 1. We will run a much heavier, slower PL/pgSQL block. By adding a small pg_sleep delay into the loop, we stretch the execution time to roughly 15–20 seconds. This gives you plenty of time to look at Terminal 2 and see autovacuum wake up and fight the dead tuples concurrently.

```
-- In Terminal 1: Run a slower, massive churn loop
DO $$
BEGIN
    FOR i IN 1..40 LOOP
        -- Algorithms constantly adjusting their bid/ask prices
        UPDATE order_book 
        SET price = price + (random() * 0.50 - 0.25) 
        WHERE status = 'OPEN';
        
        -- Cancelling a subset of orders
        UPDATE order_book 
        SET status = 'CANCELLED' 
        WHERE order_id % 40 = i;
        
        -- Artificial delay to allow autovacuum to kick off concurrently
        PERFORM pg_sleep(0.4); 
    END LOOP;
END $$;
```

#### Step 3: Catching Autovacuum Live
While the script in Terminal 1 is running, look over at Terminal 2.

Because we lowered autovacuum_vacuum_threshold to 1000, you will see a row pop up in pg_stat_progress_vacuum. You are looking at a live background worker vacuuming your table while your code is still updating it!

What to observe in Terminal 2:

phase: You will watch it cycle from scanning heap to vacuuming indexes and vacuuming heap.

num_dead_tuples: You will see exactly how many dead rows the worker has identified and cleared.

#### Step 4: Reviewing the Battle History
Once the churn loop finishes, we can check how many times the autovacuum daemon had to step in automatically during our test.

```
-- Check the table statistics
SELECT 
    relname AS table_name,
    n_dead_tup AS remaining_dead_tuples,
    autovacuum_count,
    last_autovacuum
FROM pg_stat_user_tables 
WHERE relname = 'order_book';
```

###### Sample output
```
postgres_workshop=# -- Check the table statistics
SELECT
    relname AS table_name,
    n_dead_tup AS remaining_dead_tuples,
    autovacuum_count,
    last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'order_book';
 table_name | remaining_dead_tuples | autovacuum_count |        last_autovacuum
------------+-----------------------+------------------+-------------------------------
 order_book |                     0 |                5 | 2026-06-06 21:30:00.310556+00
(1 row)

postgres_workshop=#
```

Observe the autovacuum_count. Because our thresholds were so low and the churn was so aggressive, you will likely see that autovacuum triggered multiple times in those few seconds to keep the table clean.


#### Step 5: (Optional) Checking the PostgreSQL Server Logs
If you have access to the actual PostgreSQL server log files (or docker logs), autovacuum logs its actions when it takes a long time or when configured to do so. You will see lines like this confirming its background success:

```
LOG:  automatic vacuum of table "postgres.public.order_book": index scans: 1
pages: 0 removed, 1218 remain, 0 skipped due to pins, 0 skipped frozen
tuples: 98114 removed, 100000 remain, 0 are dead but not yet removable
```

```
-- For a high-update transactions table
ALTER TABLE transactions SET (
  autovacuum_vacuum_threshold = 50,
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_analyze_threshold = 50,
  autovacuum_analyze_scale_factor = 0.01,
  autovacuum_vacuum_cost_delay = 2,
  autovacuum_vacuum_cost_limit = 1000
);

-- For audit log tables (mostly inserts, few updates)
ALTER TABLE audit_logs SET (
  autovacuum_vacuum_threshold = 5000,
  autovacuum_vacuum_scale_factor = 0.1,
  autovacuum_freeze_min_age = 50000000
);
```
