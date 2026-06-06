### High Availability and Disaster Recovery

A reliable PostgreSQL architecture must survive both the failure of a single node and the accidental deletion of data by a user.
HA Stacks: Patroni, Etcd, and HAProxy

High Availability in PostgreSQL is achieved by combining several specialized tools into a cohesive "stack." The industry standard for automated failover is Patroni.

Patroni: A Python-based cluster manager that runs on each database node. It manages the PostgreSQL process and interacts with a Distributed Configuration Store (DCS).

Etcd: The DCS that serves as the "source of truth." It maintains a leader key with a Time-to-Live (TTL). The Patroni node holding the leader key is the primary.

HAProxy: A load balancer that routes application traffic. It uses health checks against the Patroni REST API to determine which node is currently the primary (endpoint /primary) and which are replicas (endpoint /replica).1

### Laboratory: Simulating Automated Failover
In this lab, we use a Podman or Docker Compose environment to observe how Patroni handles the sudden loss of the primary node.

```
git clone https://github.com/patroni/patroni
cd patroni
```

```
podman build -t patroni .
```
### Podman compose to setup the Patroni Clusterd Postgres
```
podman compose up -d
```

```mermaid
graph TD
    %% Define external entities
    subgraph Host_Machine ["Host Machine (Mac M1)"]
        direction TB
        
        %% Client Applications
        subgraph Applications ["External Access"]
            direction LR
            psql_client[("SQL Clients <br/> (pgAdmin4, psql)")]
            browser[("Web Browser <br/> (HAProxy Stats)")]
        
            %% Port Mappings
            host_p5050(["localhost:5050"])
            host_p5001(["localhost:5001"])
        end

        %% Podman Environment
        subgraph Podman_Compose ["Podman Compose Environment"]
            direction TB
            
            %% The custom Network
            subgraph Container_Network ["Podman Network: patroni_demo (Bridge)"]
                direction TB
                
                %% HAProxy Service
                container_haproxy[["Container: <br/><b>demo-haproxy</b><br/>(haproxy)"]]

                %% Patroni / PostgreSQL Service
                subgraph Patroni_Cluster ["PostgreSQL HA Cluster (Streaming Replication)"]
                    direction LR
                    container_patroni1[["Container: <br/><b>demo-patroni1</b><br/>(patroni/postgres)"]]
                    container_patroni2[["Container: <br/><b>demo-patroni2</b><br/>(patroni/postgres)"]]
                    container_patroni3[["Container: <br/><b>demo-patroni3</b><br/>(patroni/postgres)"]]
                end

                %% etcd / DCS Service
                subgraph etcd_Cluster ["etcd Cluster (DCS Quorum)"]
                    direction LR
                    container_etcd1[["Container: <br/><b>demo-etcd1</b><br/>(etcd)"]]
                    container_etcd2[["Container: <br/><b>demo-etcd2</b><br/>(etcd)"]]
                    container_etcd3[["Container: <br/><b>demo-etcd3</b><br/>(etcd)"]]
                end
            end
        end
    end

    %% -- Define Flows --

    %% External Connections (via mapped ports)
    psql_client --> host_p5050
    host_p5050 --> container_haproxy
    
    browser --> host_p5001
    host_p5001 --> container_haproxy

    %% Internal Traffic (via container name DNS)
    
    %% HAProxy routing to the Leader (thicker line == main path)
    container_haproxy ==>|Routes SQL to Leader| container_patroni1
    container_haproxy -.->|Checks Health| container_patroni2
    container_haproxy -.->|Checks Health| container_patroni3

    %% Patroni inter-node communication (Streaming Replication)
    container_patroni1 ==> container_patroni2
    container_patroni1 ==> container_patroni3

    %% Patroni talking to the Distributed Configuration Store
    container_patroni1 -.-> etcd_Cluster
    container_patroni2 -.-> etcd_Cluster
    container_patroni3 -.-> etcd_Cluster

    %% etcd internal quorum communication
    container_etcd1 <==> container_etcd2
    container_etcd1 <==> container_etcd3
    container_etcd2 <==> container_etcd3

    %% Define Node Styles (This part is stable)
    classDef external fill:#f9f,stroke:#333,stroke-width:2px,color:black;
    classDef port fill:#ff9,stroke:#333,stroke-width:1px,stroke-dasharray: 5 5,color:black;
    classDef network fill:#e1f5fe,stroke:#0277bd,stroke-width:2px,color:black;
    classDef service fill:#fff,stroke:#333,stroke-width:1px,color:black;
    classDef main fill:#f5f5f5,stroke:#333,stroke-width:2px,stroke-dasharray: 5 5,color:black;

    class host_p5050,host_p5001 port;
    class psql_client,browser external;
    class container_haproxy,container_patroni1,container_patroni2,container_patroni3,container_etcd1,container_etcd2,container_etcd3 service;
    class Container_Network network;
    class Host_Machine main;
```

### 1. Check current cluster status

```
podman exec -it  demo-patroni1 patronictl list
```

##### Samaple output for reference
```
avannala@Q2HWTCX6H4 patroni % podman exec -it  demo-patroni1 patronictl list
+ Cluster: demo (7648343233083748380) --------+----+-------------+-----+------------+-----+
| Member   | Host       | Role    | State     | TL | Receive LSN | Lag | Replay LSN | Lag |
+----------+------------+---------+-----------+----+-------------+-----+------------+-----+
| patroni1 | 10.89.1.14 | Leader  | running   |  1 |             |     |            |     |
| patroni2 | 10.89.1.15 | Replica | streaming |  1 |   0/404F9F0 |   0 |  0/404F9F0 |   0 |
| patroni3 | 10.89.1.11 | Replica | streaming |  1 |   0/404F9F0 |   0 |  0/404F9F0 |   0 |
+----------+------------+---------+-----------+----+-------------+-----+------------+-----+
```

### 2. Create an admin Role to login via PgAdmin 

NOTE: Leader node should use to run when running create/write commands

```
podman exec -it  demo-patroni1 psql -d postgres -c "CREATE ROLE admin WITH LOGIN SUPERUSER PASSWORD 'password';"
```

### 3 Lets load some sample data

```
podman exec -it  demo-patroni1 psql -d postgres 
```

### 2. Simulate failure by stopping the leader

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
  dhi.io/etcd:3-debian-dev
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
  d2cio/patroni

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
  d2cio/patroni
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