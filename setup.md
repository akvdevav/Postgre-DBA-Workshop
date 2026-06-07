### Podman install doc
```
https://podman.io/docs/installation
```

### Windows
```
https://github.com/podman-container-tools/podman/blob/main/docs/tutorials/podman-for-windows.md
```

### MAC
```
brew install podman
```

### Setting up Postgres in Podman

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


### Select queries with performance impact
```
WITH asset_valuations AS (
    SELECT 
        p.user_id,
        SUM(p.quantity * a.current_price) AS total_asset_value
    FROM portfolios p
    JOIN assets a ON p.asset_id = a.asset_id
    GROUP BY p.user_id
),
cash_balances AS (
    SELECT 
        user_id,
        SUM(balance) AS total_cash
    FROM accounts
    WHERE currency = 'USD'
    GROUP BY user_id
)
SELECT 
    u.user_id,
    u.full_name,
    u.email,
    COALESCE(c.total_cash, 0) AS total_cash_usd,
    COALESCE(v.total_asset_value, 0) AS total_portfolio_usd,
    (COALESCE(c.total_cash, 0) + COALESCE(v.total_asset_value, 0)) AS total_net_worth
FROM users u
LEFT JOIN cash_balances c ON u.user_id = c.user_id
LEFT JOIN asset_valuations v ON u.user_id = v.user_id
WHERE u.kyc_status = TRUE
ORDER BY total_net_worth DESC
LIMIT 100;
```

```
SELECT 
    u.full_name,
    a.asset_class,
    a.ticker,
    p.quantity,
    p.average_buy_price,
    a.current_price,
    (a.current_price - p.average_buy_price) * p.quantity AS unrealized_pnl,
    CASE 
        WHEN a.current_price > p.average_buy_price THEN 'Profit'
        WHEN a.current_price < p.average_buy_price THEN 'Loss'
        ELSE 'Break Even'
    END AS position_status
FROM portfolios p
JOIN users u ON p.user_id = u.user_id
JOIN assets a ON p.asset_id = a.asset_id
WHERE p.quantity > 0 
  AND a.asset_class IN ('crypto', 'stock')
ORDER BY unrealized_pnl DESC;
```

```
WITH user_volumes AS (
    SELECT 
        o.user_id,
        COUNT(o.order_id) AS total_orders,
        SUM(o.quantity * COALESCE(o.price_limit, a.current_price)) AS total_trading_volume
    FROM orders o
    JOIN assets a ON o.asset_id = a.asset_id
    WHERE o.status = 'filled' 
      AND o.created_at >= NOW() - INTERVAL '30 days'
    GROUP BY o.user_id
)
SELECT 
    u.full_name,
    v.total_orders,
    v.total_trading_volume,
    RANK() OVER (ORDER BY v.total_trading_volume DESC) AS volume_rank,
    NTILE(4) OVER (ORDER BY v.total_trading_volume DESC) AS volume_quartile
FROM user_volumes v
JOIN users u ON v.user_id = u.user_id
WHERE v.total_trading_volume > 100;
```

```
WITH daily_ledger_stats AS (
    SELECT 
        account_id,
        DATE(created_at) AS transaction_date,
        type AS transaction_type,
        COUNT(ledger_id) AS daily_transaction_count,
        SUM(amount) AS daily_volume
    FROM ledger
    WHERE created_at >= NOW() - INTERVAL '90 days'
    GROUP BY account_id, DATE(created_at), type
)
SELECT 
    d.transaction_date,
    u.email,
    a.account_type,
    d.transaction_type,
    d.daily_transaction_count,
    d.daily_volume
FROM daily_ledger_stats d
JOIN accounts a ON d.account_id = a.account_id
JOIN users u ON a.user_id = u.user_id
WHERE d.daily_transaction_count > 50 -- Flagging accounts with high daily activity
   OR d.daily_volume > 100.00
ORDER BY d.transaction_date DESC, d.daily_volume DESC;
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