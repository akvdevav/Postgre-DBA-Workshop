
GRANT pg_monitor TO admin;

podman network create monitoring_net


podman run -d \
  --name pg_exporter \
  --network monitoring_net \
  -e DATA_SOURCE_NAME="postgresql://postgres_exporter:your_secure_password@<postgres_container_ip_or_name>:5432/postgres?sslmode=disable" \
  -p 9187:9187 \
  quay.io/prometheuscommunity/postgres-exporter:latest



  podman run -d \
  --name pg_exporter \
  --network monitoring_net \
  -e DATA_SOURCE_NAME="postgresql://admin:password@my-postgres:5432/postgres?sslmode=disable" \
  -p 9187:9187 \
  quay.io/prometheuscommunity/postgres-exporter:latest



  podman run -d \
  --name prometheus \
  --network monitoring_net \
  -p 9090:9090 \
  -v ~/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:Z \
  prom/prometheus


  podman run -d \
  --name prometheus \
  --network monitoring_net \
  -p 9090:9090 \
  -v /Users/avannala/Documents/workspace/postgres-dba-workshop/prometheus.yaml:/etc/prometheus/prometheus.yml:Z \
  prom/prometheus


  podman run -d \
  --name grafana \
  --network monitoring_net \
  -p 3000:3000 \
  grafana/grafana


