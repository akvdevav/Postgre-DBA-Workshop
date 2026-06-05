### Laboratory: Deep-Level Shared Buffer Visualization
The objective of this laboratory is to utilize the pg_buffercache extension to inspect the real-time state of the shared memory segment. This provides practitioners with the ability to see exactly which tables and indexes are resident in memory and the frequency of their access based on the clock-sweep algorithm's usage count.

### Step 1: Deployment of the Introspection Engine
The pg_buffercache module is a contrib extension that must be created within the specific database context. It requires superuser privileges or membership in the pg_monitor role to access the underlying shared memory pointers.

```
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
```

### Step 2: Relation-Based Cache Distribution Analysis
To identify which database objects are consuming the most cache space, we execute an aggregation query. This allows the engineer to validate whether "hot" tables—those most frequently queried—are appropriately cached or if memory is being wasted on large, infrequently accessed tables


```
SELECT 
    c.relname AS relation_name,
    count(*) AS buffers,
    pg_size_pretty(count(*) * 8192) AS size_in_cache,
    ROUND(100.0 * count(*) / (SELECT setting::integer FROM pg_settings WHERE name = 'shared_buffers'), 2) AS cache_percentage,
	usagecount, 
	count(*) AS page_count
FROM pg_buffercache b
INNER JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
AND b.reldatabase IN (0, (SELECT oid FROM pg_database WHERE datname = current_database()))
GROUP BY c.relname,usagecount 
ORDER BY 2 DESC
LIMIT 10;
```

### Step 3: Usage Count and Eviction Vulnerability
PostgreSQL manages the lifecycle of pages in the buffer cache using a "clock-sweep" algorithm. Each buffer is assigned a usagecount (0–5). Each time a backend accesses a page, the count is incremented. The background writer periodically sweeps through, decrementing these counts. A count of 0 indicates a "cold" page that is a candidate for eviction.

```
SELECT usagecount, count(*) AS page_count
FROM pg_buffercache
GROUP BY usagecount
ORDER BY usagecount;
```

