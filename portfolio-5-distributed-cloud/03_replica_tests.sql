-- 03_replica_tests.sql : proves the replica is a real read-only copy of the primary.
-- Primary = /var/run/postgresql:5432, replica = /tmp:55432 (Unix sockets, no TCP).
-- One script that switches servers itself.
\set ON_ERROR_STOP on
\pset pager off

\echo '=== 1. Who is who (primary) ==='
\connect -reuse-previous=off pensions - /var/run/postgresql 5432
SELECT 'PRIMARY' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;

\echo '=== 2. Who is who (replica) ==='
\connect -reuse-previous=off pensions - /tmp 55432
SELECT 'REPLICA' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;

\echo '=== 3. A write on the replica is rejected (expected error below) ==='
\set ON_ERROR_STOP off
INSERT INTO pension_fund (fund_code, fund_name, risk_profile) VALUES ('X', 'Should fail', 'LOW');
\set ON_ERROR_STOP on

\echo '=== 4. Write on the primary ==='
\connect -reuse-previous=off pensions - /var/run/postgresql 5432
DROP TABLE IF EXISTS replica_check;
CREATE TABLE replica_check (id SERIAL PRIMARY KEY, note TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now());
SELECT 'check-' || to_char(clock_timestamp(), 'HH24MISS') AS marker \gset
INSERT INTO replica_check (note) VALUES (:'marker');
SELECT pg_current_wal_lsn() AS primary_lsn \gset
SELECT :'marker' AS marker_written_on_primary;
SELECT pg_sleep(1);

\echo '=== 5. The row arrives on the replica ==='
\connect -reuse-previous=off pensions - /tmp 55432
SELECT note AS marker_seen_on_replica, created_at FROM replica_check WHERE note = :'marker';
SELECT pg_wal_lsn_diff(pg_last_wal_replay_lsn(), :'primary_lsn') >= 0 AS replica_caught_up;

\echo '=== 6. Same data on both servers ==='
SELECT count(*) AS replica_contribution_rows FROM contribution;
\connect -reuse-previous=off pensions - /var/run/postgresql 5432
SELECT count(*) AS primary_contribution_rows FROM contribution;

\echo '=== 7. Replication status on the primary ==='
SELECT application_name, state, sync_state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
  FROM pg_stat_replication;
DROP TABLE replica_check;
\echo '=== End of replica tests ==='
