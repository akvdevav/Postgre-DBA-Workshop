# Postgre-DBA-Workshop

This repository is a hands-on PostgreSQL DBA workshop covering performance troubleshooting, storage internals, high availability, recovery, and database machine learning.

![1](1.png)

## Workshop overview

- `Labs/Lab1.md` — Shared buffer and `pg_buffercache` visualization for memory residency and hot object analysis.
- `Labs/Lab2.md` — Index benchmarking with large time-series data, comparing B-Tree and BRIN indexes.
- `Labs/Lab3.md` — MVCC, bloat, and autovacuum diagnostics with `pgstattuple`.
- `Labs/Lab4.md` — Simulating autovacuum-disabled workloads and dead tuple accumulation in a high-frequency order book.
- `Labs/Lab5.md` — Advanced observability using `pg_stat_activity`, wait events, `pg_stat_statements`, and XID wraparound monitoring.
- `Labs/Lab6.md` — High availability and disaster recovery with Patroni, Etcd, and HAProxy.
- `Labs/Lab7.md` — Point-in-Time Recovery (PITR) and backup strategies using WAL archiving and pgBackRest.
- `Labs/Lab8.md` — In-database machine learning with PostgresML, RBAC, and model auditing.
- `Labs/Lab9.md` — ML risk governance in a financial workload, separating training and inference roles.

## Useful references

- `setup.md` — Environment preparation and workshop setup instructions.
- `docker.md` — Docker-related guidance for container-based PostgreSQL environments.
- `admin_queries.md` — Useful administrative queries for PostgreSQL monitoring and troubleshooting.
- `alldbs_backup.sql` — Example backup and restore SQL snippets.
- `monitoring.md` — Monitoring strategies and PostgreSQL metrics.

## Getting started

1. Read `setup.md` to prepare the environment.
2. Open the `Labs/` folder and start with `Labs/Lab1.md`.
3. Review the follow-up labs in order to build on core DBA skills.

---

> Note: The `Labs/` directory contains both lab exercises and supporting setup/debug documents (`Labs/asetup.md`, `Labs/debug.md`).

