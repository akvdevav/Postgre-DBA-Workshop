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


