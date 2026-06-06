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
