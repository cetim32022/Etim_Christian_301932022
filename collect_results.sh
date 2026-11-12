#!/usr/bin/env bash
# Gathers the real output of your own run into my_results.txt (nothing is typed in by hand).
cd "$(dirname "${BASH_SOURCE[0]}")"
OUT=my_results.txt
P1=portfolio-1-database-design; P2=portfolio-2-query-optimisation; P3=portfolio-3-transactions-concurrency
P4=portfolio-4-nosql; P5=portfolio-5-distributed-cloud
{
echo "MIT 8103 results - Etim Christian Ime (2026/A/MIT/0925) - pensions"
echo "Collected: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Git commits:"; git log --oneline 2>/dev/null | head -12
show() { # title file regex
  echo; echo "=============== $1 ==============="
  if [ -f "$2" ]; then grep -E "$3" "$2" | head -${4:-60}; else echo "(no log: $2)"; fi
}
show "P1 row counts and constraint tests" $P1/p1_output.log 'employee_count|rsa_account_count|contribution_count|fund_price_count|TEST|PASS|FAIL' 40
show "P2 before/after (plans and times)" $P2/p2_output.log 'PHASE|QUERY|Q[0-9]|Execution Time|Seq Scan|Index Scan|Index Only|Bitmap Heap' 80
show "P3 transactions (SQL)" $P3/p3_output.log '.' 40
show "P3 race demos" $P3/race_demos_output.log 'Part [0-9]|BUG|FIX|T1:|T2:|DEADLOCK|READ COMMITTED|REPEATABLE READ|Start balance|End balance' 70
show "P4 MongoDB COLLSCAN vs IXSCAN" $P4/p4_output.log 'Inserted|Stage|Docs|Time ms|Time \(ms\)|SUMMARY' 20
show "P5 partitions" $P5/p5_output.log 'already partitioned|partition_name|contribution_|rows$|default_partition_rows|Execution Time|Partitions|Scan on|Seq Scan' 60
echo; echo "=============== P5 replica (full log) ==============="
if [ -f $P5/replication_output.log ]; then cat $P5/replication_output.log; else echo "(no log: $P5/replication_output.log)"; fi
} > "$OUT" 2>&1
echo "Wrote $OUT ($(wc -l < "$OUT") lines)"
command -v code >/dev/null 2>&1 && code "$OUT" || true
