### Laboratory: Deep-Level Shared Buffer Visualization
The objective of this laboratory is to utilize the pg_buffercache extension to inspect the real-time state of the shared memory segment. This provides practitioners with the ability to see exactly which tables and indexes are resident in memory and the frequency of their access based on the clock-sweep algorithm's usage count.


#### Create a newtwork for container communication
```
podman network create workshop
```

#### Deploy postgres in podman 

```
podman run -d \
  --name my-postgres \
  --network workshop \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  postgres:latest \
  -c shared_preload_libraries='pg_stat_statements' \
  -c pg_stat_statements.track=all
```

#### Creating an addition user to validate permissions

```
CREATE ROLE admin WITH LOGIN SUPERUSER PASSWORD 'password';
```

#### pg_stat_statements
The pg_stat_statements extension is arguably the single most important performance monitoring tool in the entire PostgreSQL ecosystem.

When you run CREATE EXTENSION pg_stat_statements;, you are enabling a built-in module that tracks detailed planning and execution statistics for every single SQL query run against your database. It is the gold standard for finding bottlenecks, slow queries, and resource hogs.

```
CREATE EXTENSION pg_stat_statements;
```

#### pg_buffercache is your memory X-ray machine.

When you run CREATE EXTENSION IF NOT EXISTS pg_buffercache;, you are unlocking the ability to look directly inside PostgreSQL's RAM to see exactly which tables and indexes are taking up your memory in real-time.

```
CREATE EXTENSION IF NOT EXISTS pg_buffercache;
```

####

```
CREATE EXTENSION IF NOT EXISTS pgstattuple;
```

```
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

```
CREATE DATABASE postgres_workshop;
```

```
psql -h localhost -p 5432 -U postgres -d postgres
```

### Tables 

```
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
FROM generate_series(1, 10000000);

-- Generate 1,000,000 rows of random initial trade data
INSERT INTO trade_history (user_id, symbol, trade_type, quantity, price, status, trade_date)
SELECT 
    floor(random() * 10000 + 1)::INT, -- Random user ID between 1 and 10,000
    
    -- Generates a random 4-letter uppercase string (ASCII 65 to 90)
    chr(floor(random() * 26 + 65)::INT) || 
    chr(floor(random() * 26 + 65)::INT) || 
    chr(floor(random() * 26 + 65)::INT) || 
    chr(floor(random() * 26 + 65)::INT), 
    
    (ARRAY['BUY', 'SELL'])[floor(random() * 2 + 1)], -- Random trade type
    floor(random() * 990 + 10)::INT, -- Random share quantity (10 to 1,000)
    (random() * 490 + 10)::NUMERIC(10, 2), -- Random execution price ($10.00 to $500.00)
    'PENDING', -- All new trades start as pending
    NOW() - (random() * interval '30 days') -- Random date within the last 30 days
FROM generate_series(1, 10000000);
```


```
-- Extensions & Custom Types
CREATE TYPE transaction_type AS ENUM ('deposit', 'withdrawal', 'transfer', 'buy', 'sell');
CREATE TYPE order_status AS ENUM ('pending', 'filled', 'cancelled', 'rejected');
CREATE TYPE asset_class AS ENUM ('stock', 'crypto', 'forex', 'commodity');

-- 1. Core Users Table
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    full_name TEXT NOT NULL,
    kyc_status BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Banking: Cash Accounts
CREATE TABLE accounts (
    account_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    currency CHAR(3) DEFAULT 'USD',
    balance NUMERIC(20, 4) DEFAULT 0.0000 CHECK (balance >= 0),
    account_type TEXT DEFAULT 'checking',
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Trading: Assets & Portfolios
CREATE TABLE assets (
    asset_id SERIAL PRIMARY KEY,
    ticker TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    asset_class asset_class NOT NULL,
    current_price NUMERIC(20, 4)
);

CREATE TABLE portfolios (
    portfolio_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    asset_id INTEGER REFERENCES assets(asset_id),
    quantity NUMERIC(20, 8) DEFAULT 0 CHECK (quantity >= 0),
    average_buy_price NUMERIC(20, 4),
    UNIQUE(user_id, asset_id)
);

-- 4. Transactions & Order History
CREATE TABLE orders (
    order_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id),
    asset_id INTEGER REFERENCES assets(asset_id),
    side TEXT CHECK (side IN ('buy', 'sell')),
    quantity NUMERIC(20, 8) NOT NULL,
    price_limit NUMERIC(20, 4), -- For limit orders
    status order_status DEFAULT 'pending',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ledger (
    ledger_id BIGSERIAL PRIMARY KEY,
    account_id UUID REFERENCES accounts(account_id),
    amount NUMERIC(20, 4) NOT NULL,
    type transaction_type NOT NULL,
    reference_id UUID, -- Links to order_id or external transfer
    created_at TIMESTAMPTZ DEFAULT NOW()
);



INSERT INTO users (email, full_name, kyc_status, created_at)
SELECT 
    'user_' || i || '_' || substr(md5(random()::text), 1, 6) || '@example.com',
    'Test User ' || i,
    random() > 0.2, -- 80% chance of KYC being true
    NOW() - (random() * interval '365 days') -- Random date in the last year
FROM generate_series(1, 1000000) AS i;



INSERT INTO accounts (user_id, currency, balance, account_type, updated_at)
SELECT 
    user_id,
    (ARRAY['USD', 'EUR', 'GBP', 'JPY'])[floor(random() * 4 + 1)], -- Pick random currency
    (random() * 10000000)::numeric(20,4), -- Random balance up to 100,000
    (ARRAY['checking', 'savings', 'margin'])[floor(random() * 3 + 1)],
    NOW() - (random() * interval '30 days')
FROM users
LIMIT 1000000;


INSERT INTO assets (ticker, name, asset_class, current_price)
SELECT 
    'TICK' || i,
    'Asset Corp ' || i,
    (ARRAY['stock', 'crypto', 'forex', 'commodity']::asset_class[])[floor(random() * 4 + 1)],
    (random() * 5000 + 1)::numeric(20,4) -- Price between 1 and 5001
FROM generate_series(1, 1000000) AS i;



WITH user_sample AS (SELECT user_id, row_number() OVER () as rn FROM users),
     asset_sample AS (SELECT asset_id, row_number() OVER () as rn FROM assets)
INSERT INTO portfolios (user_id, asset_id, quantity, average_buy_price)
SELECT 
    u.user_id,
    a.asset_id,
    (random() * 500)::numeric(20,8),
    (random() * 5000 + 1)::numeric(20,4)
FROM user_sample u
JOIN asset_sample a ON u.rn = a.rn; -- Maps 1 random asset to 1 user

WITH user_sample AS (SELECT user_id, row_number() OVER () as rn FROM users),
     asset_sample AS (SELECT asset_id, row_number() OVER () as rn FROM assets)
INSERT INTO orders (user_id, asset_id, side, quantity, price_limit, status, created_at)
SELECT 
    u.user_id,
    a.asset_id,
    (ARRAY['buy', 'sell'])[floor(random() * 2 + 1)],
    (random() * 100 + 1)::numeric(20,8),
    (random() * 5000 + 1)::numeric(20,4),
    (ARRAY['pending', 'filled', 'cancelled', 'rejected']::order_status[])[floor(random() * 4 + 1)],
    NOW() - (random() * interval '365 days')
FROM user_sample u
-- Shift the join slightly so they aren't trading the exact same asset as their portfolio
JOIN asset_sample a ON a.rn = ((u.rn * 7) % 1000000) + 1;

WITH user_sample AS (SELECT user_id, row_number() OVER () as rn FROM users),
     asset_sample AS (SELECT asset_id, row_number() OVER () as rn FROM assets)
INSERT INTO orders (user_id, asset_id, side, quantity, price_limit, status, created_at)
SELECT 
    u.user_id,
    a.asset_id,
    (ARRAY['buy', 'sell'])[floor(random() * 2 + 1)],
    (random() * 100 + 1)::numeric(20,8),
    (random() * 5000 + 1)::numeric(20,4),
    (ARRAY['pending', 'filled', 'cancelled', 'rejected']::order_status[])[floor(random() * 4 + 1)],
    NOW() - (random() * interval '365 days')
FROM user_sample u
-- Shift the join slightly so they aren't trading the exact same asset as their portfolio
JOIN asset_sample a ON a.rn = ((u.rn * 7) % 1000000) + 1;

WITH account_sample AS (SELECT account_id, row_number() OVER () as rn FROM accounts)
INSERT INTO ledger (account_id, amount, type, created_at)
SELECT 
    a.account_id,
    (random() * 1000000 + 10)::numeric(20,4),
    (ARRAY['deposit', 'withdrawal', 'transfer', 'buy', 'sell']::transaction_type[])[floor(random() * 5 + 1)],
    NOW() - (random() * interval '180 days')
FROM account_sample a;
```


### Table for trades

```
CREATE TABLE trades_raw (
    trade_id SERIAL PRIMARY KEY,
    symbol VARCHAR(10),
    user_id INT,
    price DECIMAL(12, 2),
    quantity INT,
    trade_time TIMESTAMP NOT NULL
);

CREATE INDEX idx_trades_raw_time ON trades_raw(trade_time);


CREATE TABLE trades_partitioned (
    trade_id SERIAL,
    symbol VARCHAR(10),
    user_id INT,
    price DECIMAL(12, 2),
    quantity INT,
    trade_time TIMESTAMP NOT NULL
) PARTITION BY RANGE (trade_time);

-- Creating partitions for a 3-month window
CREATE TABLE trades_2026_01 PARTITION OF trades_partitioned
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE trades_2026_02 PARTITION OF trades_partitioned
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE trades_2026_03 PARTITION OF trades_partitioned
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

-- Index on the parent (propagates to partitions)
CREATE INDEX idx_trades_part_time ON trades_partitioned(trade_time);


INSERT INTO trades_raw (symbol, user_id, price, quantity, trade_time)
SELECT 
    (ARRAY['AAPL', 'TSLA', 'GOOGL', 'AMZN'])[floor(random() * 4 + 1)],
    floor(random() * 1000 + 1),
    (random() * 1000)::decimal(12,2),
    floor(random() * 100 + 1),
    '2026-01-01'::timestamp + random() * (interval '90 days')
FROM generate_series(1, 1000000);

-- Sync the partitioned table with the same data
INSERT INTO trades_partitioned SELECT * FROM trades_raw;
```

### Row Counts
```
SELECT                                                      
  schemaname AS schema_name, 
  relname AS table_name,                                                       
  n_live_tup AS row_count                                                                
FROM                                               
  pg_stat_user_tables                                                       
ORDER BY                              
  row_count DESC;
```


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

