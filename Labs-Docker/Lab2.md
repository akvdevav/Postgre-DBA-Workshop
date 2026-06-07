### Laboratory: Benchmarking Specialized Indexes
In this laboratory, we simulate a high-volume dataset to observe the performance and storage trade-offs between B-Tree and BRIN indexes.

### Step 1: High-Volume Data Generation
We create a table simulating a sensor network that generates sequential time-series data.14

SQL

```
CREATE TABLE sensor_logs (
    id BIGSERIAL PRIMARY KEY,
    reading DECIMAL,
    recorded_at TIMESTAMP DEFAULT now()
);

-- Generate 5 million rows of ordered data
INSERT INTO sensor_logs (reading, recorded_at)
SELECT random(), x
FROM generate_series('2024-01-01 00:00:00'::timestamp, 
                     '2024-12-31 23:59:59'::timestamp, 
                     '6 seconds'::interval) x;
```

### Step 2: Storage and Performance Comparison
We compare the size of a standard B-Tree against a BRIN index on the recorded_at column.


```
EXPLAIN ANALYSE SELECT * FROM SENSOR_LOGS;
```

```
-- Standard B-Tree
CREATE INDEX idx_logs_btree ON sensor_logs (recorded_at);
```

```
-- Measure size
SELECT pg_size_pretty(pg_relation_size('idx_logs_btree')); -- Result: ~110 MB
```

```
EXPLAIN ANALYSE SELECT * FROM SENSOR_LOGS;
```

```
-- Drop and create BRIN
DROP INDEX idx_logs_btree;
CREATE INDEX idx_logs_brin ON sensor_logs USING BRIN (recorded_at);
```

```
-- Measure size
SELECT pg_size_pretty(pg_relation_size('idx_logs_brin')); -- Result: ~48 KB
```

```
EXPLAIN ANALYSE SELECT * FROM SENSOR_LOGS;
```

The BRIN index represents a reduction in storage requirements of approximately 99.9% while still allowing for extremely fast date-range lookups. This efficiency is contingent upon the data being physically ordered; if the data were shuffled, the BRIN min/max ranges would overlap extensively, rendering the index useless.
