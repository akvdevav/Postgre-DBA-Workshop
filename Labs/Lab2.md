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


#### Database Tuning Lab: Index Performance, Execution Plans, and Sizing

Objective: Understand how indexing impacts query execution plans, measure the performance gains of different index strategies across multiple tables, and analyze the physical storage footprint of those indexes.

Step 1: Lab Setup and Data Generation
First, we will create two related tables—customers and orders—and populate them with enough data to force the query optimizer to make meaningful decisions.


```
-- 1. Create the Tables
CREATE TABLE customers (
    customer_id SERIAL PRIMARY KEY,
    first_name VARCHAR(50),
    last_name VARCHAR(50),
    status VARCHAR(20),
    signup_date DATE
);

CREATE TABLE orders (
    order_id SERIAL PRIMARY KEY,
    customer_id INT REFERENCES customers(customer_id),
    order_date DATE,
    total_amount NUMERIC(10, 2),
    shipping_status VARCHAR(20)
);

-- 2. Generate 100,000 Customers
INSERT INTO customers (first_name, last_name, status, signup_date)
SELECT 
    'First' || g, 
    'Last' || g, 
    CASE WHEN random() < 0.8 THEN 'ACTIVE' ELSE 'INACTIVE' END,
    CURRENT_DATE - (random() * 3650)::int
FROM generate_series(1, 100000) AS g;

-- 3. Generate 1,000,000 Orders (randomly assigned to customers)
INSERT INTO orders (customer_id, order_date, total_amount, shipping_status)
SELECT 
    (random() * 99999 + 1)::int,
    CURRENT_DATE - (random() * 3650)::int,
    (random() * 1000)::numeric(10,2),
    CASE WHEN random() < 0.9 THEN 'SHIPPED' ELSE 'PENDING' END
FROM generate_series(1, 1000000) AS g;
```


#### Step 2: Baseline Performance (No Indexes)

Before adding any indexes (other than the default Primary Keys), let's run two common queries and review their baseline execution plans.

Query A: High-Selectivity Filter
Find all pending orders with a value over $900.

```
EXPLAIN ANALYZE 
SELECT * FROM orders 
WHERE shipping_status = 'PENDING' AND total_amount > 900;
```
Expected Plan: You will see a Seq Scan (Sequential Scan) on the orders table. The execution time will likely be 50ms - 150ms depending on hardware, because the database must read all 1,000,000 rows to find the matches.


#### Query B: Multi-Table Join
Find the total revenue from 'ACTIVE' customers who joined in the last year.

```
EXPLAIN ANALYZE 
SELECT c.status, SUM(o.total_amount)
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.status = 'ACTIVE' 
  AND c.signup_date >= CURRENT_DATE - 365
GROUP BY c.status;
```
Expected Plan: You will likely see a Hash Join with Seq Scans on both customers and orders.


#### Step 3: Applying Indexes
Now, let's create a few different indexes to target these specific queries.

```
-- Index 1: Standard B-Tree on a Foreign Key (Helps with Joins)
CREATE INDEX idx_orders_customer_id ON orders(customer_id);

-- Index 2: Composite Index (Helps with Query A)
CREATE INDEX idx_orders_status_amount ON orders(shipping_status, total_amount);

-- Index 3: Partial Index (Highly optimized for a specific business rule)
CREATE INDEX idx_customers_active_recent ON customers(signup_date) 
WHERE status = 'ACTIVE';
```

#### Step 4: Measuring Execution Plan Changes
Re-run the exact same queries from Step 2. Notice how the query optimizer adapts.

```
EXPLAIN ANALYZE 
SELECT * FROM orders 
WHERE shipping_status = 'PENDING' AND total_amount > 900;
```
New Plan: You should now see a Bitmap Index Scan on idx_orders_status_amount followed by a Bitmap Heap Scan.

Performance Gain: Execution time should drop from ~100ms down to under 5ms.



```
EXPLAIN ANALYZE 
SELECT c.status, SUM(o.total_amount)
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.status = 'ACTIVE' 
  AND c.signup_date >= CURRENT_DATE - 365
GROUP BY c.status;
```
New Plan: You should see an Index Scan on idx_customers_active_recent and an Index Scan on idx_orders_customer_id powering a Nested Loop or highly optimized Hash Join.



#### Step 5: Index Sizing and Storage Overhead
Indexes speed up reads, but they consume disk space and slow down INSERT/UPDATE operations. Let's measure exactly how much space our new indexes are consuming compared to the base tables.

```
-- Check the size of the base tables
SELECT 
    relname AS table_name, 
    pg_size_pretty(pg_table_size(oid)) AS table_size
FROM pg_class 
WHERE relname IN ('customers', 'orders');

-- Check the size of every index on the orders and customers tables
SELECT 
    tablename, 
    indexname, 
    pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
FROM pg_indexes 
WHERE tablename IN ('customers', 'orders')
ORDER BY tablename, indexname;
```
What to look for:

Notice how large idx_orders_customer_id is compared to the orders table itself (it often takes up 15-20% of the table's size).

Look at idx_customers_active_recent. Because this is a Partial Index (it only indexes rows where status = 'ACTIVE'), its storage footprint is significantly smaller than a standard index, making it highly efficient for disk space and memory.


### Additional commands 

```
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM your_table;
```

```
SET enable_mergejoin = off;
-- Your query goes here
```

- https://pg-hint-plan.readthedocs.io/en/latest/installation.html
- https://github.com/ossc-db/pg_hint_plan
- https://www.postgresql.org/docs/current/using-explain.html
- https://www.postgresql.org/docs/current/planner-stats.html

