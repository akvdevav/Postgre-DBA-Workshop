### The "Cruft" Problem: MVCC, Bloat, and Autovacuum
PostgreSQL’s Multi-Version Concurrency Control (MVCC) implementation ensures that "readers never block writers." This is achieved by never overwriting data in place. When a row is updated, PostgreSQL marks the old version as "dead" and inserts a new version. These dead rows, or "tuples," continue to occupy space on disk until they are removed by the VACUUM process.6
"Bloat" occurs when the rate of dead tuple generation outpaces the ability of autovacuum to clean them up. A bloated table or index consumes more disk space, requires more I/O to scan, and degrades cache efficiency because the system must load pages filled with data that is no longer visible to any transaction.21

| Bloat Type | Cause | Diagnostic Query/Tool | Resolution |
| :---: | :---: | :---: | :---: |
| **Table Bloat** | Massive DELETEs or UPDATEs. | `pgstattuple` extension  | `VACUUM FULL` (Locks table) or `pg_repack`. |
| **Index Bloat** | Frequent updates on indexed columns.  | `pg_stat_user_indexes` and size comparison scripts. | `REINDEX INDEX CONCURRENTLY`.  |
| **WAL Bloat** | Long-running transactions or replication lag. | `pg_stat_replication` and `pg_replication_slots`. | Resolve long transactions or drop orphaned slots. |


The autovacuum daemon is the primary defense against bloat. It is triggered when the number of dead tuples exceeds a threshold defined as autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor * reltuples). For large tables, the default scale_factor of 0.2 (20%) is often too high; on a table with 100 million rows, 20 million rows must be modified before a vacuum is triggered. Reducing this factor to 0.01 (1%) ensures more frequent, less intensive cleanup cycles.6

### Workshop Lab: Understanding MVCC, Bloat, and Autovacuum
Prerequisites: Connect and Setup

```
-- Enable the diagnostic extension
CREATE EXTENSION IF NOT EXISTS pgstattuple;

-- Create the trading table
CREATE TABLE trade_history (
    trade_id BIGSERIAL PRIMARY KEY,
    user_id INT NOT NULL,
    symbol VARCHAR(10) NOT NULL,
    trade_type VARCHAR(4) NOT NULL,
    quantity INT NOT NULL,
    price NUMERIC(10, 2) NOT NULL,
    status VARCHAR(15) NOT NULL,
    trade_date TIMESTAMP NOT NULL
)WITH (autovacuum_enabled = false);
```

```
-- Generate 1,000,000 rows of random initial trade data
INSERT INTO trade_history (user_id, symbol, trade_type, quantity, price, status, trade_date)
SELECT 
    floor(random() * 10000 + 1)::INT, -- Random user ID between 1 and 10,000
    (ARRAY['AAPL', 'MSFT', 'AMZN', 'NVDA', 'JPM', 'GS', 'V', 'SQ'])[floor(random() * 8 + 1)], -- Random stock
    (ARRAY['BUY', 'SELL'])[floor(random() * 2 + 1)], -- Random trade type
    floor(random() * 990 + 10)::INT, -- Random share quantity (10 to 1,000)
    (random() * 490 + 10)::NUMERIC(10, 2), -- Random execution price ($10.00 to $500.00)
    'PENDING', -- All new trades start as pending
    NOW() - (random() * interval '30 days') -- Random date within the last 30 days
FROM generate_series(1, 1000000);
```


Step 1: Establish the Baseline
Before simulating the trading day's end, let's observe the physical size of the table and its internal tuple structure.
SQL

```
-- Check the physical file size of the table
SELECT pg_size_pretty(pg_relation_size('trade_history')) AS table_size;
```

```
-- Check the internal health
SELECT * FROM pgstattuple('trade_history');
```

Notice that dead_tuple_percent is roughly 0%. The table is tightly packed because we just inserted fresh data.

### Step 2: Simulate Trade Settlements (Generating Bloat)
In a real environment, background workers constantly update trade statuses. Let's simulate an end-of-day batch process that marks older trades as SETTLED. This will trigger a massive UPDATE operation.
```
-- Settle approximately 50% of the trades (those older than 15 days)
UPDATE trade_history 
SET status = 'SETTLED' 
WHERE trade_date < NOW() - interval '15 days';
UPDATE trade_history
SET status = 'SOLD'
WHERE trade_date < NOW() - interval '15 days';
```

```
-- Check the physical file size again
SELECT pg_size_pretty(pg_relation_size('trade_history')) AS table_size;
```

```
-- Check the internal health again
SELECT * FROM pgstattuple('trade_history');
```

Observe the MVCC "Cruft" Problem: The physical table size has grown significantly. Because PostgreSQL marks the old PENDING rows as dead rather than overwriting them, you will now see a massive spike in dead_tuple_count and dead_tuple_percent.
Step 3: Manual VACUUM vs. VACUUM FULLWorkshop Lab: MVCC, Bloat, and Autovacuum in Trading Systems
Prerequisites: Schema Setup and Data Generation
First, connect to the database and enable the extension that allows us to diagnose table health. Then, we will create a trade_history table and populate it with 1,000,000 rows of randomized trading data.



Now, let's attempt to clean up the dead tuples. We will start with a standard VACUUM.

```
-- Run a standard manual vacuum
VACUUM VERBOSE trade_history;
```

```
-- Check internal health
SELECT * FROM pgstattuple('trade_history');
```

-- Check table size again
SELECT pg_size_pretty(pg_relation_size('trade_history')) AS table_size;
Crucial takeaway: The dead_tuple_percent drops to near zero, and free_percent spikes. However, the table size did not shrink. Standard vacuum marks the space as reusable for future trades, but does not return it to the operating system.
To physically reclaim the disk space and shrink the file, we must rewrite the table using VACUUM FULL.
SQL
-- Run VACUUM FULL (Warning: Takes an exclusive lock! Blocks trading operations!)
VACUUM FULL VERBOSE trade_history;

-- Check the final size and health
SELECT pg_size_pretty(pg_relation_size('trade_history')) AS table_size;
SELECT * FROM pgstattuple('trade_history');
The physical table size has shrunk back down, and the free space has been reclaimed.
Step 4: Tuning Autovacuum for High-Velocity Tables
Running VACUUM FULL in production requires downtime, which is unacceptable for a financial exchange. The best defense is ensuring Autovacuum runs aggressively enough to reuse space before the table grows out of control.
The default threshold (autovacuum_vacuum_scale_factor of 20%) means 200,000 trades would have to update before vacuum kicks in. Let's tune this specific table to vacuum after just 1% of rows change.
SQL
-- View current table-specific options (blank by default)
SELECT relname, reloptions FROM pg_class WHERE relname = 'trade_history';

-- Lower the threshold to 1% specifically for this table
ALTER TABLE trade_history SET (autovacuum_vacuum_scale_factor = 0.01);

-- Verify the tuning change was applied
SELECT relname, reloptions FROM pg_class WHERE relname = 'trade_history';
