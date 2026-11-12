#!/usr/bin/env bash
# P5 - streaming replica of the pensions primary, run as your own user.
# Primary: Unix socket /var/run/postgresql port 5432. Replica: Unix socket /tmp port 55432.
# No TCP, no passwords (peer auth as your own user), nothing in /etc is changed.
set -euo pipefail
PGV="$(ls /usr/lib/postgresql | sort -V | tail -1)"
BIN="/usr/lib/postgresql/$PGV/bin"
RDIR="$HOME/pensions_replica"

if [ -d "$RDIR" ]; then "$BIN/pg_ctl" -D "$RDIR" -m fast stop >/dev/null 2>&1 || true; rm -rf "$RDIR"; fi

"$BIN/pg_basebackup" -h /var/run/postgresql -p 5432 -U "$(id -un)" -D "$RDIR" -X stream -R -c fast
chmod 700 "$RDIR"

# Ubuntu keeps the config files in /etc, so the base backup has none: write minimal ones.
cat > "$RDIR/postgresql.conf" <<CONF
port = 55432
listen_addresses = ''
unix_socket_directories = '/tmp'
hot_standby = on
max_connections = 200
cluster_name = 'pensions_replica'
CONF
echo "local all all trust" > "$RDIR/pg_hba.conf"
: > "$RDIR/pg_ident.conf"

"$BIN/pg_ctl" -D "$RDIR" -l "$RDIR/replica.log" -w start
for i in $(seq 1 20); do psql -h /tmp -p 55432 -d pensions -Atc "SELECT pg_is_in_recovery()" 2>/dev/null | grep -q t && break; sleep 1; done
echo "Replica up: in_recovery=$(psql -h /tmp -p 55432 -d pensions -Atc 'SELECT pg_is_in_recovery()')"
