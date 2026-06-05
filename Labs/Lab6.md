### High Availability and Disaster Recovery

A reliable PostgreSQL architecture must survive both the failure of a single node and the accidental deletion of data by a user.
HA Stacks: Patroni, Etcd, and HAProxy

High Availability in PostgreSQL is achieved by combining several specialized tools into a cohesive "stack." The industry standard for automated failover is Patroni.1

Patroni: A Python-based cluster manager that runs on each database node. It manages the PostgreSQL process and interacts with a Distributed Configuration Store (DCS).

Etcd: The DCS that serves as the "source of truth." It maintains a leader key with a Time-to-Live (TTL). The Patroni node holding the leader key is the primary.

HAProxy: A load balancer that routes application traffic. It uses health checks against the Patroni REST API to determine which node is currently the primary (endpoint /primary) and which are replicas (endpoint /replica).1

### Laboratory: Simulating Automated Failover
In this lab, we use a Docker Compose environment to observe how Patroni handles the sudden loss of the primary node.8

### 1. Check current cluster status
docker compose exec patroni1 patronictl list

### 2. Simulate failure by stopping the leader
docker stop postgres_primary_container

### 3. Observe Patroni electing a new leader and HAProxy updating its route
docker compose logs -f haproxy


The system should complete the failover in under 30 seconds, ensuring minimal downtime for the application. The use of a DCS like Etcd prevents "Split-Brain" scenarios, where two nodes both believe they are the primary, which would lead to catastrophic data divergence.1
