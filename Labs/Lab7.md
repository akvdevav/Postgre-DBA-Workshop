#### Backup Strategy and Point-in-Time Recovery (PITR)

High Availability is not a substitute for backups. A "Split-Brain" or a DROP TABLE command is replicated instantly to all nodes in an HA cluster. Reliability, therefore, requires a robust backup engine like pgBackRest.
pgBackRest improves upon traditional tools like pg_dump or pg_basebackup by offering:

Parallelism: Backing up and restoring using multiple CPU cores and I/O streams.

Delta Restore: Only restoring the files that have changed, significantly reducing Recovery Time Objectives (RTO).

Point-in-Time Recovery (PITR): The ability to "replay" the Write Ahead Logs to a specific millisecond, allowing the engineer to restore the database to a state just before a data-loss event.


### Laboratory: Point-in-Time Recovery
To perform PITR, we first configure pgBackRest to archive WAL files to a repository (local or S3).

### 🕵️‍♂️ Workshop Lab: The Great Crypto Heist (Podman PITR)

##### The Scenario
An attacker has executed a malicious DROP TABLE on our core financial ledger. Because this is a containerized environment, the damage is catastrophic—unless we can use Point-in-Time Recovery (PITR) to rewind the transaction history to the exact millisecond before the hacker struck.

##### 🛠️ Step 1: Spin Up the Managed Podman Infrastructure
We will launch a PostgreSQL container with WAL Archiving Enabled.


# 1. Clean up any leftover host directories from prior test runs
```
rm -rf ~/pg_archive && mkdir -p ~/pg_archive && chmod 777 ~/pg_archive
```

# 2. Spin up our primary instance with open host network auth
```
podman run -d --name crypto-db \
  --user 0 \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=crypto-secret \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -v ~/pg_archive:/mnt/server_archive:Z \
  postgres:latest \
  -c wal_level=replica \
  -c archive_mode=on \
  -c archive_command='cp %p /mnt/server_archive/%f'
```

#### 💰 Step 2: Establish the Golden State
Connect to the database from your Mac machine using your local psql client:

```
psql -h localhost -d postgres -U postgres
```
Now, execute the following SQL to build our crypto ledger and seed it with corporate funds:

```
-- Create the secure wallet ledger
CREATE TABLE crypto_wallets (
    wallet_id SERIAL PRIMARY KEY,
    owner_name VARCHAR(50),
    coin_type VARCHAR(10),
    balance NUMERIC(15, 4),
    last_updated TIMESTAMP DEFAULT NOW()
);
```

```
-- Deposit the corporate funds
INSERT INTO crypto_wallets (owner_name, coin_type, balance) VALUES
('Corporate Treasury', 'BTC', 4500.0000),
('Cold Storage Alpha', 'ETH', 25000.0000),
('Hot Wallet', 'SOL', 150000.0000);
```

```
-- Verify our assets are live and secure
SELECT * FROM crypto_wallets;
```

-- Disconnect back to your Mac terminal
```
\q
```

#### 🧯 Step 3: Authorize Replication & Extract the Base Backup
To capture a healthy baseline snapshot of the database, we must allow replication traffic through PostgreSQL's host authentication controls, and then execute pg_basebackup.

# 1. Open up pg_hba.conf within the container to trust local replication traffic
```
podman exec crypto-db bash -c "echo 'host replication all all trust' >> /var/lib/postgresql/data/pg_hba.conf"
```

```
podman exec crypto-db bash -c "echo 'host replication all all trust' >> /var/lib/postgresql/18/docker/pg_hba.conf"
```

# 2. Reload the PostgreSQL configuration so the security rules apply instantly
```
podman exec crypto-db psql -U postgres -c "SELECT pg_reload_conf();"
```

# 3. Clear old fragments and create a secure backup directory in your Home directory
```
rm -rf ~/pg_base_backup && mkdir -p ~/pg_base_backup
```

# 4. Stream the backup data directly out of the database onto your Mac laptop
```
pg_basebackup -h localhost -U postgres -D ~/pg_base_backup -Fp -Xs
```

#### ⏱️ Step 4: Note the "Safe Time"
Reconnect to your database to grab the exact timestamp right before the heist occurs.

```
psql -h localhost -d postgres -U postgres
```

Check the database clock:
```
SELECT clock_timestamp();
```

📝 RECORD YOUR SAFE TIMESTAMP HERE:
Copy the entire timestamp string including its timezone offset (e.g., 2026-06-07 07:15:22 ). You will paste this exact value in 


#### 🚨 Step 5: THE HEIST OCCURS!
The rogue agent's payload executes. The table is dropped, and we force the database to cycle its write-ahead log to guarantee the crime is exported out to our persistent archive disk.

Run this destructive SQL block:

```
-- 💥 THE HEIST
DROP TABLE crypto_wallets;
```

```
-- Force Postgres to push the current transaction log segment out to ~/pg_archive
SELECT pg_switch_wal();
```

-- Disconnect from the compromised database
```
\q
```
Now that the logs are flushed, completely destroy the compromised database instance:

```
podman stop crypto-db && podman rm crypto-db
```

#### 🕰️ Step 6: Configure the Recovery Targets
We will inject instructions into our configuration files to direct the recovery engine to stop processing logs the exact millisecond before the DROP TABLE command took place.

Run this entire block on your Mac terminal. Make sure to replace the timestamp below with your actual safe timestamp from Step 4:

# 1. Point the recovery engine to our archived log storage path inside the container
```
echo "restore_command = 'cp /mnt/server_archive/%f %p'" >> ~/pg_base_backup/postgresql.auto.conf
```

# 2. Tell the engine exactly when to halt log playback (PASTE YOUR TIMESTAMP HERE)
```
echo "recovery_target_time = '2026-06-07 07:15:22.123456+00'" >> ~/pg_base_backup/postgresql.auto.conf
```

# 3. Configure the engine to promote the node to writable status once playback completes
```
echo "recovery_target_action = 'promote'" >> ~/pg_base_backup/postgresql.auto.conf
```
# 4. Create the mandatory signal file that flags to PostgreSQL it must start up in Recovery Mode
```
touch ~/pg_base_backup/recovery.signal
```

🚀 Step 7: Transition to a Native Volume & Launch Recovery
To prevent macOS shared file permissions (chown: Operation not permitted) from breaking the recovery process, we transfer our files into a native Podman Volume and spin up the recovered server.

```
podman volume rm crypto_recovery_vol
```

# 1. Create a native volume managed purely inside the Podman Linux VM
```
podman volume create crypto_recovery_vol
```

# 2. Use a temporary container helper to cleanly migrate files and set standard postgres ownerships
```
podman run --rm -it \
  --user 0 \
  -v ~/pg_base_backup:/mac_backup:Z \
  -v crypto_recovery_vol:/podman_vol \
  postgres:latest bash -c '
    BACKUP_DIR=$(dirname $(find /mac_backup -name PG_VERSION | head -n 1))
    cp -a $BACKUP_DIR/* /podman_vol/
    chown -R postgres:postgres /podman_vol
  '
```

# 3. Spin up our brand new recovery server using a custom, isolated PGDATA path
```
podman run -d --name crypto-recovered \
  -p 5432:5432 \
  -e POSTGRES_PASSWORD=crypto-secret \
  -e POSTGRES_HOST_AUTH_METHOD=trust \
  -e PGDATA=/var/lib/postgresql/recovered_data \
  -v crypto_recovery_vol:/var/lib/postgresql/recovered_data \
  -v ~/pg_archive:/mnt/server_archive:Z \
  postgres:latest
```

#### 🏆 Step 8: Verify the Assets are Restored!
Give the container 5 to 10 seconds to boot up, scan the recovery.signal file, and replay your transaction logs from the archive storage.

Once ready, reconnect to the server:

```
psql -h localhost -d postgres -U postgres
```

Run the validation query:
```
SELECT * FROM crypto_wallets;
```

```
Expected Output:
Your ledger is completely intact, exactly as it existed before the drop table command:

Plaintext
 wallet_id |     owner_name     | coin_type |   balance   |        last_updated        
-----------+--------------------+-----------+-------------+----------------------------
         1 | Corporate Treasury | BTC       |   4500.0000 | 2026-06-07 07:12:01.442811
         2 | Cold Storage Alpha | ETH       |  25000.0000 | 2026-06-07 07:12:01.442811
         3 | Hot Wallet         | SOL       | 150000.0000 | 2026-06-07 07:12:01.442811
(3 rows)
```

Once the restore is complete, starting the PostgreSQL process will cause it to enter "recovery mode," where it pulls the necessary WAL files from the pgBackRest repository and applies them sequentially until the target timestamp is reached.38


### Extra Commands for Debugging WAL

WAL files are saved inside your PostgreSQL data directory. You can find their exact location by running this command inside the psql console
```
SHOW data_directory;
```

Check WAL Metrics and Status (SQL).You can use built-in SQL functions to monitor WAL activity without leaving the database.Find the Current Log File and LocationTo find the active Log Sequence Number (LSN) and the specific file name currently being written to, run:

```
SELECT pg_current_wal_lsn(), pg_walfile_name(pg_current_wal_lsn());

```

Check General WAL Statistics (PostgreSQL 14+)To view performance stats like total bytes written, record counts, and write times, query the pg_stat_wal view

```
SELECT * FROM pg_stat_wal;
```

Count Unarchived WAL FilesIf you are managing replication or archiving, you can count how many files are waiting to sync:
```
SELECT count(*) FROM pg_ls_dir('pg_wal/archive_status') WHERE pg_ls_dir ~ E'\\.ready$';
```

 Read Binary WAL ContentTo decode the binary logs into human-readable data, use one of the following tools:Option A: Use pg_waldump (Command Line)The pg_waldump utility allows you to parse WAL segments directly from your server's terminal. You must run this command as the postgres user or a user with physical read access to the data directory.

 ```
 pg_waldump /var/lib/postgresql/data/pg_wal/000000010000000000000001
 ```

 To see a summary of resource managers (DML/DDL types) inside a file:

 ```
 pg_waldump --stats /var/lib/postgresql/data/pg_wal/000000010000000000000001
 ```


```
CREATE EXTENSION pg_walinspect;
```

```
SELECT name
FROM pg_ls_dir('pg_wal') AS name
WHERE name !~ 'archive_status'
ORDER BY name DESC
LIMIT 5;
```

```
SELECT
    pg_current_wal_lsn() AS "Current_Active_LSN",
    pg_current_wal_insert_lsn() AS "Current_Insert_LSN";
```

```
SELECT start_lsn, end_lsn, resource_manager, description 
FROM pg_get_wal_records_info('0/20265B0', '0/20265B0');
```