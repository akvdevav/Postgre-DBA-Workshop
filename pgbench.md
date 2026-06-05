SELECT
  schemaname AS schema_name,
  relname AS table_name,
  n_live_tup AS row_count
FROM
  pg_stat_user_tables
ORDER BY
  row_count DESC;


SELECT state, count(*) 
FROM pg_stat_activity 
GROUP BY state;



podman exec my-postgres -it pgbench -U postgres -i -s 10 postgres

podman exec my-postgres pgbench -U postgres -c 50 -j 10 -T 60 -P 5 postgres