#### Backup Strategy and Point-in-Time Recovery (PITR)

High Availability is not a substitute for backups. A "Split-Brain" or a DROP TABLE command is replicated instantly to all nodes in an HA cluster. Reliability, therefore, requires a robust backup engine like pgBackRest.
pgBackRest improves upon traditional tools like pg_dump or pg_basebackup by offering:
Parallelism: Backing up and restoring using multiple CPU cores and I/O streams.
Delta Restore: Only restoring the files that have changed, significantly reducing Recovery Time Objectives (RTO).
Point-in-Time Recovery (PITR): The ability to "replay" the Write Ahead Logs to a specific millisecond, allowing the engineer to restore the database to a state just before a data-loss event.


### Laboratory: Point-in-Time Recovery
To perform PITR, we first configure pgBackRest to archive WAL files to a repository (local or S3).


# Configuration in postgresql.conf
archive_mode = on
archive_command = 'pgbackrest --stanza=demo archive-push %p'

# The Restore Command for PITR
sudo -u postgres pgbackrest \
    --stanza=demo \
    --type=time \
    "--target=2024-03-06 10:15:00" \
    --delta \
    restore


Once the restore is complete, starting the PostgreSQL process will cause it to enter "recovery mode," where it pulls the necessary WAL files from the pgBackRest repository and applies them sequentially until the target timestamp is reached.38
