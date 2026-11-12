#!/usr/bin/env bash
# MIT 8103 - Etim Christian Ime (2026/A/MIT/0925) - pensions
# Runs Portfolio 1 to 5 in order, commits and pushes after each, then writes my_results.txt.
# Usage (from your repo folder):  bash runall.sh      or  bash runall.sh 3   (start from P3)
set -uo pipefail
START="${1:-1}"
DB=pensions
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"
KIT="$HOME/kit/advanced-database-portfolio"
ZIP="$REPO/Etim_Christian_FIXED.zip"

# 1. find the kit (it can vanish when the Codespace restarts)
if [ ! -d "$KIT/portfolio-1-database-design" ]; then
  if [ -f "$ZIP" ]; then mkdir -p "$HOME/kit" && unzip -oq "$ZIP" -d "$HOME/kit"; fi
fi
[ -d "$KIT/portfolio-1-database-design" ] || { echo "!!! kit not found - drag Etim_Christian_FIXED.zip into the repo folder and run again"; exit 1; }

# 2. start the databases in case the Codespace slept; re-run setup if the database is gone
PGV="$(ls /usr/lib/postgresql | sort -V | tail -1)"
pg_lsclusters | grep -q online || sudo pg_ctlcluster "$PGV" main start || sudo service postgresql start
pgrep -x mongod >/dev/null || sudo runuser -u mongodb -- "$(command -v mongod)" --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --port 27017 --fork >/dev/null
sleep 2
if ! psql -d "$DB" -Atc 'SELECT 1' >/dev/null 2>&1 || ! python3 -c 'import psycopg2' 2>/dev/null; then
  echo ">>> database or driver missing - running setup.sh first"
  bash "$REPO/setup.sh" || { echo "!!! setup failed - send Joseph the screen text"; exit 1; }
fi

P="psql -d $DB -v ON_ERROR_STOP=1"
run_p1() { set -e; for f in 01_schema 02_indexes 03_seed_data 04_bulk_data 05_constraint_tests; do echo "--- $f.sql"; $P -f $f.sql; done; }
run_p2() { set -e; $P -f 01_queries.sql >/dev/null; $P -f 02_explain_analyze.sql; }
run_p3() { set -e; $P -f 01_transactions.sql; echo "--- race_demos.py"; python3 race_demos.py 2>&1 | tee race_demos_output.log; }
run_p4() { set -e; for f in 01_setup 02_data_and_queries 03_bulk_and_index_demo; do echo "--- $f.js"; mongosh --quiet $DB $f.js; done; }
run_p5() { set -e; $P -f 01_partitioning.sql; echo "--- replica"; bash 02_replica_setup.sh; psql -d $DB -v ON_ERROR_STOP=1 -f 03_replica_tests.sql 2>&1 | tee replication_output.log; }

step() { # number, folder, log name, message
  local N="$1" D="$2" L="$3" M="$4"
  [ "$N" -lt "$START" ] && return 0
  echo; echo "================ P$N: $M ================"
  mkdir -p "$REPO/$D" && cp -r "$KIT/$D/." "$REPO/$D/"
  ( cd "$REPO/$D"; "run_p$N" ) 2>&1 | tee "$REPO/$D/$L"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "!!! P$N FAILED - send Joseph $D/$L"; exit 1; fi
  git add -A >/dev/null 2>&1; git commit -qm "Portfolio $N: $M" >/dev/null 2>&1 || true; git push -q >/dev/null 2>&1 || echo "(push skipped)"
}
step 1 portfolio-1-database-design p1_output.log "database design, bulk data and constraint tests"
step 2 portfolio-2-query-optimisation p2_output.log "query optimisation with EXPLAIN ANALYZE"
step 3 portfolio-3-transactions-concurrency p3_output.log "transactions and race-condition demos"
step 4 portfolio-4-nosql p4_output.log "MongoDB collections, aggregations and index demo"
step 5 portfolio-5-distributed-cloud p5_output.log "partitioning and streaming replica"

cp "$KIT/collect_results.sh" "$REPO/collect_results.sh" 2>/dev/null || true
bash "$REPO/collect_results.sh"
git add -A >/dev/null 2>&1; git commit -qm "Add collected results" >/dev/null 2>&1 || true; git push -q >/dev/null 2>&1 || true
echo "ALL DONE - copy the text of my_results.txt (Ctrl+A, Ctrl+C) and send it to Joseph"
