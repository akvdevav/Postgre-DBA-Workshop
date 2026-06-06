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


### Laboratory: The Arena of Automated Failover
In this lab, we are leaving the training wheels of compose behind. We will manually deploy our cluster into a Podman network, crown a primary leader, and then ruthlessly pull the plug on it to watch Patroni's automated failover leap into action.

### Step 1: Build the Arena (Create the Network)
First, we need an isolated network so our containers can communicate via DNS names.

```
podman network create pg-arena
```

### Step 2: Deploy the Referee (Etcd)
Etcd acts as the source of truth for our cluster. It will keep track of who is in charge.

```
podman run -d --name etcd \
  --network pg-arena \
  -e ALLOW_NONE_AUTHENTICATION=yes \
  docker.io/bitnami/etcd:latest
```

### Step 3: Enter the Champion (Deploy Node 1)
We spin up our first Patroni node. Because it's the first one to connect to Etcd, it will automatically grab the leader lock and become the Primary node.

```
podman run -d --name pg-node1 \
  --network pg-arena \
  -e PATRONI_ETCD3_HOSTS="etcd:2379" \
  -e PATRONI_SCOPE="demo-cluster" \
  -e PATRONI_NAME="pg-node1" \
  -e PATRONI_SUPERUSER_PASSWORD="supersecretpassword" \
  docker.io/bitnami/patroni:latest
```

### Step 4: Enter the Challenger (Deploy Node 2)
Now we deploy the second node. It will see that pg-node1 already holds the leader lock in Etcd, so it will politely become a Replica and start syncing data.

```
podman run -d --name pg-node2 \
  --network pg-arena \
  -e PATRONI_ETCD3_HOSTS="etcd:2379" \
  -e PATRONI_SCOPE="demo-cluster" \
  -e PATRONI_NAME="pg-node2" \
  -e PATRONI_SUPERUSER_PASSWORD="supersecretpassword" \
  docker.io/bitnami/patroni:latest
```

Step 5: Check the Scoreboard
Let's ask Patroni for the current state of the cluster. You should see pg-node1 listed as the Leader.
(Note: It may take 10-15 seconds for the nodes to fully initialize on the first run).

```
podman exec -it pg-node2 patronictl list
```

### Step 6: Trigger the Disaster!
Time for chaos. We simulate a sudden, catastrophic server failure by killing the primary node with no warning.

```
podman stop pg-node1
```

### Step 7: Watch the Magic Happen
Immediately run the scoreboard command again.

```
podman exec -it pg-node2 patronictl list
```

### What you are observing:
Within seconds, Patroni on pg-node2 realizes the TTL on the Etcd leader key has expired because pg-node1 is no longer updating it. pg-node2 immediately promotes itself to Leader!

The system completes this failover in under 30 seconds, ensuring minimal downtime for an application. Because Patroni relies on Etcd as the single source of truth, it completely prevents "Split-Brain" scenarios—meaning even if pg-node1 suddenly wakes back up, it will realize it lost the lock and demote itself to a replica, saving you from catastrophic data divergence.