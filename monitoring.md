
### Create a newtwork for container communication
```
podman network create workshop
```

### Deploy you postgres db

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

### Create roles and permision for monitoring
```
CREATE ROLE admin WITH LOGIN SUPERUSER PASSWORD 'password';
```

```
GRANT pg_monitor TO admin;
```

### Deploy postgre exporter that will scrape the metrics

```
  podman run -d \
  --name pg_exporter \
  --network workshop \
  -e DATA_SOURCE_NAME="postgresql://admin:password@my-postgres:5432/postgres?sslmode=disable" \
  -p 9187:9187 \
  quay.io/prometheuscommunity/postgres-exporter:latest
```

### Deploy prometheus

```
  podman run -d \
  --name prometheus \
  --network workshop \
  -p 9090:9090 \
  -v /Users/avannala/Documents/workspace/postgres-dba-workshop/prometheus.yaml:/etc/prometheus/prometheus.yml:Z \
  prom/prometheus
```

#### Deploy Grafana

```
  podman run -d \
  --name grafana \
  --network workshop \
  -p 3000:3000 \
  grafana/grafana
```
- Default creds for grafana admin/admin
- Setup data source: http://prometheus:9090
- Setup dashbaord: use the grafana-dashboard.json


