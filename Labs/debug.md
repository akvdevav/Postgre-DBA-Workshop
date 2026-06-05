### Synthesis: The Professional Troubleshooting and Optimization Kit

The final objective of this framework is to provide the attendee with a codified mental model for database performance engineering.

#### Troubleshooting Workflow: The Mental Model
When a performance incident is reported, the engineer should follow a structured diagnostic path to isolate the root cause:
Level 1: System Saturation
Check OS-level metrics (CPU, RAM, Disk I/O, Network).
If CPU is high, check pg_stat_activity for "active" queries without wait events.
If I/O is high, check for DataFileRead wait events and queries with high shared_blks_read in pg_stat_statements.
Level 2: Contention and Blocking
Use pg_blocking_pids() to identify lock hierarchies.
Identify "idle in transaction" sessions that are holding locks and preventing autovacuum from reclaiming space.
Check for "Wait Event: Lock" in pg_stat_activity.
Level 3: Query Inefficiency
Extract the top queries from pg_stat_statements.
Run EXPLAIN (ANALYZE, BUFFERS) on the slowest queries.
Check for Sequential Scans on large tables and evaluate if an index (B-Tree, GIN, or BRIN) is missing.
Level 4: Maintenance Health
Check table and index bloat levels using pgstattuple.
Monitor XID age to prevent wraparound lockouts.
Validate that autovacuum workers are not being cancelled by heavy DML or long-running analytics queries.
Performance Optimization Kit: Essential SQL Library
A library of prepared scripts ensures that a DBA can respond to incidents with precision and speed.
Script 1: Identifying the Top 10 Most Bloated Tables
This script uses the pg_stat_user_tables view to find candidates for manual vacuuming or tuning.

SQL


SELECT 
    schemaname, 
    relname AS table_name, 
    n_dead_tup, 
    n_live_tup, 
    ROUND(n_dead_tup::numeric / GREATEST(n_live_tup, 1) * 100, 2) AS dead_pct,
    last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY dead_pct DESC
LIMIT 10;


Script 2: Finding Missing Indexes
This heuristic query identifies tables with high volumes of sequential scans where the scans are actually retrieving very few rows—a classic sign that an index could significantly improve performance.

SQL


SELECT 
    relname, 
    seq_scan - idx_scan AS scan_diff, 
    seq_tup_read / seq_scan AS avg_tup_read_per_scan
FROM pg_stat_user_tables
WHERE seq_scan > 100 AND seq_tup_read > 10000
ORDER BY 2 DESC
LIMIT 10;


### 1. Finding PostgreSQL Database Configurations

The easiest way to find and understand PostgreSQL configurations is directly inside the database using the pg_settings system view. This is vastly superior to just reading the postgresql.conf file because pg_settings includes the active values, the units (e.g., 8kB pages vs. MB), and a description of what the setting actually does.

#### The DBA Discovery Query:
SQL

```
-- View the most important settings, their current values, and descriptions
SELECT name, setting, unit, short_desc 
FROM pg_settings 
WHERE category IN ('Resource Usage / Memory', 'Autovacuum', 'Write-Ahead Log');
```

Key PostgreSQL Configurations for Financial DBAs:
Setting
Category
What it does
Enterprise Context
shared_buffers
Memory
Dedicated RAM for Postgres caching.
Usually set to 25% of total system RAM.
work_mem
Memory
RAM used per operation (like sorting/joins).
Crucial to increase for complex financial reports.
maintenance_work_mem
Memory
RAM for maintenance tasks.
Increase this to speed up VACUUM and index creation.
max_connections
Connections
Max concurrent client connections.
High numbers waste memory. Use PgBouncer instead.
max_wal_size
WAL
How much WAL can grow before a checkpoint.
Financial systems write heavily; this needs to be large (e.g., 10GB+).

2. Finding Linux OS Level Configurations
PostgreSQL relies heavily on the Linux kernel for caching, memory management, and file I/O. If you configure Postgres to use 10,000 files, but Linux only allows an application to open 1,024, Postgres will simply crash.
You generally check these settings using sysctl and ulimit on your Linux terminal.
Key Linux OS Configurations to Check:
Open File Limits (ulimit -n):
How to find: Run ulimit -Sn (soft limit) and ulimit -Hn (hard limit).
Why it matters: PostgreSQL opens a file descriptor for every single table, index, and connection. In an enterprise system with thousands of partitions, the default Linux limit of 1024 will cause "too many open files" errors.
Where to fix: /etc/security/limits.conf
Memory Overcommit (vm.overcommit_memory):
How to find: Run sysctl vm.overcommit_memory
Why it matters: Linux loves to promise applications memory it doesn't actually have. If it suddenly runs out, the OS Out-Of-Memory (OOM) Killer will assassinate PostgreSQL to save the system. DBAs usually set this to 2 (Strict overcommit) to prevent crashes.
Where to fix: /etc/sysctl.conf
Swappiness (vm.swappiness):
How to find: Run sysctl vm.swappiness
Why it matters: Linux tries to swap inactive memory to disk. You never want Postgres shared memory swapped out to disk. Lower this from the default 60 to 1 or 10.
Where to fix: /etc/sysctl.conf
Huge Pages (vm.nr_hugepages):
How to find: Run grep HugePages /proc/meminfo
Why it matters: For databases with large shared_buffers (e.g., > 16GB), standard 4KB memory pages create massive CPU overhead. Configuring Linux Huge Pages (usually 2MB size) drastically improves performance.
3. The DBA "Cheat Code": PGTune
Instead of guessing the baseline configurations, most DBAs use a tool like PGTune (available via web browser). It is an industry-standard calculator where you input your OS type, total RAM, CPU cores, disk type, and workload type (e.g., OLTP for trading systems). It generates the exact mathematical postgresql.conf values you should start with, saving you hours of manual calculation.
