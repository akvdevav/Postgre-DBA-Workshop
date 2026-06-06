##### To find your top 5 worst-performing queries by average execution time:

```
SELECT 
    query, 
    calls, 
    round(mean_exec_time::numeric, 2) AS avg_time_ms, 
    round(total_exec_time::numeric, 2) AS total_time_ms
FROM 
    pg_stat_statements
ORDER BY 
    mean_exec_time DESC
LIMIT 5;
```

1. The Magic Feature: Query Normalization
If your application runs SELECT * FROM users WHERE id = 1 and then runs SELECT * FROM users WHERE id = 2, tracking them as two separate queries would be useless—your logs would be flooded.

pg_stat_statements automatically normalizes queries. It replaces all the hardcoded parameters with variables (like $1) and groups them together into a single statistical bucket:
SELECT * FROM users WHERE id = $1

This allows you to see the aggregate performance of that type of query, regardless of the specific data being searched.

2. What Exactly Does It Track?
Once enabled, it creates a view (a virtual table) named pg_stat_statements. When you query this view, it gives you a treasure trove of metrics for every normalized query, including:

calls: How many times this exact query has been executed. (Great for finding the "N+1" query problem).

total_exec_time / mean_exec_time: The total and average time spent executing the query in milliseconds. (Great for finding slow queries).

rows: The total number of rows retrieved or affected by the query.

shared_blks_hit vs. shared_blks_read: This tells you if the query is finding its data in RAM (cache hit) or if it's forcing the database to do slow reads from the physical hard drive.



##### 

```
SELECT
    c.relname AS table_or_index_name,
    count(*) AS buffers,
    -- Multiply buffer count by 8KB to get actual memory used
    pg_size_pretty(count(*) * 8192) AS memory_used,
    -- See how much of this data has been modified but not yet saved to disk
    round(100.0 * sum(case when isdirty then 1 else 0 end) / count(*), 1) AS percent_dirty
FROM pg_buffercache b
INNER JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
    AND b.reldatabase IN (0, (SELECT oid FROM pg_database WHERE datname = current_database()))
GROUP BY c.relname
ORDER BY buffers DESC
LIMIT 10;
```

. The Core Concept: Shared Buffers
To understand this extension, you first have to understand how PostgreSQL handles memory.

PostgreSQL does not like reading data from a physical hard drive because disks are slow. When you query data, Postgres pulls it from the disk and copies it into a massive chunk of RAM called the shared buffer cache (defined by the shared_buffers setting in your config).

If you query that same data again, Postgres reads it instantly from the RAM cache.

2. What pg_buffercache Actually Does
By default, Postgres does not tell you what is inside that RAM. You might know you have 4GB of RAM allocated to shared_buffers, but you have no idea if it's filled with your users table, your sales table, or completely wasted space.

Creating this extension gives you a system view (also named pg_buffercache) that lists every single "page" (an 8KB block of memory) currently sitting in RAM.

3. Why is this useful?
Database administrators use this extension to answer critical performance questions:

"Why is my database suddenly so slow?" (You might discover a poorly written query just flushed your entire cache and filled it with a useless logging table).

"Is my index actually being used?" (You can check if an index is actually sitting in RAM. If it isn't, Postgres isn't caching it, which might mean it's doing sequential table scans instead).

"How much memory do I actually need?" (If you see that your cache is only 20% full during peak hours, you know you are safely over-provisioned).

4. A Real-World Example Query
If you just run SELECT * FROM pg_buffercache;, the output is practically unreadable for humans because it only uses internal ID numbers (relfilenode).

To make it useful, you have to join it with the pg_class table to get the actual names of your tables and indexes. Here is the classic DBA query used to find the Top 10 memory hogs in your database:


#### View All Running Queries

```
SELECT 
    pid,
    usename AS user,
    datname AS database,
    now() - query_start AS duration,
    state,
    query
FROM pg_stat_activity
WHERE state != 'idle' 
  AND pid <> pg_backend_pid()
ORDER BY duration DESC;
```

##### View Queries Running Longer Than 5 Minutes

```
SELECT 
    pid,
    now() - query_start AS duration,
    query,
    state
FROM pg_stat_activity
WHERE state = 'active'
  AND (now() - query_start) > interval '5 minutes'
ORDER BY duration DESC;
```

#### Stop a Problematic Query

##### Cancel a single query safely (keeps the client connection open):
```
SELECT pg_cancel_backend(YOUR_QUERY_PID);
```

##### Force terminate the backend process (completely closes the client connection)
```
SELECT pg_terminate_backend(YOUR_QUERY_PID);
```

#### Checking Table-Level Transaction Age

```
SELECT c.oid::regclass as table_name,
       greatest(age(c.relfrozenxid),age(t.relfrozenxid)) as age
FROM pg_class c
LEFT JOIN pg_class t ON c.reltoastrelid = t.oid
WHERE c.relkind IN ('r', 'm');
```

What it does: This query finds the "age" (measured in number of transactions elapsed since the last whole-table vacuum) of every individual table and its associated TOAST table.

Breakdown of the components:

c.oid::regclass as table_name: Converts the internal object ID (oid) of the table into its actual human-readable text name.

pg_class c: The system catalog table that stores metadata about tables, indexes, and views.

LEFT JOIN pg_class t ON c.reltoastrelid = t.oid: Joins the main table to its TOAST table (if it has one). TOAST tables store large data fields (like long text or JSON blobs) out-of-line, and they have their own transaction ages that must be monitored.

greatest(age(c.relfrozenxid), age(t.relfrozenxid)): The age() function calculates how many transactions have passed since the table was last frozen. greatest() ensures you see the worse/older of the two ages between the main table and its TOAST table.

WHERE c.relkind IN ('r', 'm'): Filters the results to only look at regular tables ('r') and materialized views ('m'), ignoring indexes, views, or sequences.

#### Checking Database-Level Transaction Age

```
SELECT datname, age(datfrozenxid) FROM pg_database;
```

What it does: This is a high-level, bird's-eye view query. It checks the transaction age of entire databases within your Postgres cluster.

Breakdown of the components:

datname: The name of the database.

age(datfrozenxid): Looks at datfrozenxid, which represents the oldest unfrozen transaction ID across the entire database. The age() function tells you how many transactions ago that oldest record was created.

PostgreSQL Transaction ID (XID) Wraparound Monitoring

This repository provides queries and documentation for monitoring **Transaction ID (XID) Wraparound** in PostgreSQL. Transaction IDs are finite 32-bit integers (maxing out around 4 billion). To prevent data loss from a wraparound event—where the transaction counter resets to 0 and old data suddenly appears to be in the future—PostgreSQL uses a background process called `VACUUM` to "freeze" old transactions.

Use the provided scripts to proactively identify databases and specific tables getting dangerously close to the 2-billion transaction limit.

---

##### Thresholds & Action Plan

Keep a close eye on the `age` column returned by the monitoring queries. Use the following operational guidelines to interpret the results:

| Age Value | Status | Action Required |
| :--- | :---: | :--- |
| **< 100–150 Million** | 🟢 Normal | Autovacuum is handling things smoothly. No manual intervention required. |
| **> 200 Million** | 🟡 Warning | PostgreSQL will aggressively kick off anti-wraparound autovacuuming (`autovacuum_freeze_max_age`). This can cause high disk I/O spikes and performance degradation. |
| **~ 2 Billion** | 🔴 Critical | **Emergency.** PostgreSQL will shut down completely and refuse to accept new write transactions to prevent data corruption. The cluster will require manual booting into single-user mode to run `VACUUM FREEZE`. |

---


#### VACUUM FREEZE 

```
VACUUM FREEZE table_name;
```

In PostgreSQL, VACUUM FREEZE table_name; is an aggressive maintenance command used to prevent Transaction ID (XID) Wraparound, a critical state that can cause data corruption or force your database to shut down completely.

Here is a breakdown of what the command does, how it works, and when you should use it.

What it does (The Core Concept)
Every time a row is inserted, updated, or deleted in PostgreSQL, it is stamped with the ID of the transaction that created it (stored in a hidden column called xmin). PostgreSQL transaction IDs are finite 32-bit integers, meaning there are only about 4 billion possible IDs.

Because of this limit, the transaction counter eventually wraps around back to zero. When this happens, PostgreSQL needs to ensure that older data doesn't suddenly appear to have been created "in the future" (which would make it invisible to current transactions).

VACUUM FREEZE fixes this by scanning the specified table and "freezing" all visible rows.

What happens during a "Freeze"?
When you execute VACUUM FREEZE table_name;, PostgreSQL performs the following steps on that specific table:

Replaces Transaction IDs: It takes the internal transaction IDs (xmin) of all rows older than a certain threshold and converts them into a special, permanent transaction ID called FrozenTransactionId (internally represented as transaction ID 2).

Marks Rows as Permanently Valid: Any row stamped with this frozen ID is treated as being in the infinite past. It will always be visible to all current and future transactions, regardless of how high the transaction counter climbs.

Advances the Safety Counter: Once all rows in the table are frozen, PostgreSQL updates the table's internal metadata (relfrozenxid in the pg_class catalog). This resets the table's "age" back to 1, safely moving it away from the 2-billion transaction danger zone.

Reclaims Space (Standard Vacuuming): Like a normal vacuum, it also removes dead row versions (garbage left behind by updates and deletes) and frees up space.

How is it different from a regular VACUUM?
While both clean up a table, their intent and intensity differ:

Standard VACUUM: Focuses primarily on cleaning up dead rows (bloat) to reclaim space. It will only freeze rows that are exceptionally old based on your vacuum_freeze_min_age configuration setting. If a table hasn't changed much, a standard vacuum might skip pages entirely.

VACUUM FREEZE: Forces an immediate, aggressive freeze on all rows that can possibly be frozen, regardless of how recently they were modified. It forces PostgreSQL to scan the entire table thoroughly to advance the relfrozenxid counter as much as possible.

When should you run VACUUM FREEZE?
While PostgreSQL has a background process called Autovacuum that automatically triggers a freeze when a table reaches a certain age (controlled by autovacuum_freeze_max_age), you typically run it manually in these scenarios:

Emergency Prevention: If your monitoring queries show a table's transaction age creeping close to or exceeding 200 million, and autovacuum is running too slowly to catch up.

After Bulk Loads: If you have just loaded a massive amount of historical, read-only data into a table (e.g., millions of rows of logs or archives) that will rarely change, running VACUUM FREEZE immediately ensures those rows are frozen right away. This prevents autovacuum from having to waste heavy disk I/O scanning that giant table later on during peak traffic hours.

Before Major Migrations/Upgrades: Freezing tables ahead of major database operations ensures that the system doesn't unexpectedly trigger an intensive background anti-wraparound vacuum in the middle of your maintenance window.
