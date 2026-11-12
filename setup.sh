#!/usr/bin/env bash
# MIT 8103 Advanced Database Systems - Etim Christian Ime (2026/A/MIT/0925)
# Pension Fund Administration System - database: pensions
# One-time setup for GitHub Codespaces: PostgreSQL + MongoDB + python driver,
# role/database over the Unix socket (no TCP, no passwords), then copies the
# top-level files into your repo folder and commits them.
set -euo pipefail

DB=pensions
ME="$(id -un)"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(pwd)"
UBU="$(. /etc/os-release; echo "${VERSION_CODENAME:-jammy}")"

echo ">>> 1/6 packages (PostgreSQL, MongoDB)"
if [ "${SKIP_APT:-0}" != "1" ]; then
  sudo rm -f /etc/apt/sources.list.d/yarn.list
  sudo apt-get update -qq || true
  if ! command -v pg_ctlcluster >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq postgresql postgresql-contrib
  fi
  if ! command -v mongod >/dev/null 2>&1; then
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl gnupg ca-certificates
    if [ "$UBU" = "noble" ]; then MV=8.0; else MV=7.0; fi
    curl -fsSL "https://www.mongodb.org/static/pgp/server-$MV.asc" | sudo gpg --batch --yes -o "/usr/share/keyrings/mongodb-server-$MV.gpg" --dearmor
    echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-$MV.gpg ] https://repo.mongodb.org/apt/ubuntu $UBU/mongodb-org/$MV multiverse" | sudo tee "/etc/apt/sources.list.d/mongodb-org-$MV.list" >/dev/null
    sudo apt-get update -qq || true
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mongodb-org
  fi
fi

echo ">>> 2/6 start PostgreSQL"
PGV="$(ls /usr/lib/postgresql | sort -V | tail -1)"
if ! pg_lsclusters | grep -q online; then
  sudo pg_ctlcluster "$PGV" main start || sudo service postgresql start
fi
for i in $(seq 1 20); do sudo runuser -u postgres -- pg_isready -q && break; sleep 1; done

echo ">>> 3/6 role and database ($ME / $DB)"
sudo runuser -u postgres -- psql -qAt -c "SELECT 1 FROM pg_roles WHERE rolname='$ME'" | grep -q 1 \
  || sudo runuser -u postgres -- psql -q -c "CREATE ROLE \"$ME\" SUPERUSER LOGIN"
sudo runuser -u postgres -- psql -qAt -c "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 \
  || sudo runuser -u postgres -- psql -q -c "CREATE DATABASE $DB OWNER \"$ME\""
psql -d "$DB" -q -c "ALTER DATABASE $DB SET timezone TO 'Africa/Lagos'"
psql -d "$DB" -Atc "SELECT 'PostgreSQL ok: ' || current_database() || ' as ' || current_user"

echo ">>> 4/6 start MongoDB"
sudo mkdir -p /data/db /var/log/mongodb
sudo chown -R mongodb:mongodb /data/db /var/log/mongodb 2>/dev/null || true
if ! pgrep -x mongod >/dev/null; then
  sudo runuser -u mongodb -- "$(command -v mongod)" --dbpath /data/db --logpath /var/log/mongodb/mongod.log --bind_ip 127.0.0.1 --port 27017 --fork >/dev/null
fi
for i in $(seq 1 20); do mongosh --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -q 1 && break; sleep 1; done
echo "MongoDB ok: $(mongosh --quiet --eval 'db.runCommand({ping:1}).ok')"

echo ">>> 5/6 python driver psycopg2"
if ! python3 -c 'import psycopg2' 2>/dev/null; then
  pip install -q psycopg2-binary 2>/dev/null \
  || pip install -q --user psycopg2-binary 2>/dev/null \
  || pip install -q --break-system-packages psycopg2-binary 2>/dev/null \
  || pip install -q --user --break-system-packages psycopg2-binary 2>/dev/null \
  || sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq python3-psycopg2
fi
python3 -c 'import psycopg2; print("psycopg2 ok", psycopg2.__version__)'

echo ">>> 6/6 copy top-level files into the repo and commit"
if [ "$SRC" != "$REPO" ]; then
  for f in README.md setup.sh runall.sh collect_results.sh CHANGES.md; do
    [ -f "$SRC/$f" ] && cp "$SRC/$f" "$REPO/$f"
  done
  mkdir -p "$REPO/docs" && cp -r "$SRC/docs/." "$REPO/docs/"
fi
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$REPO" add -A
  git -C "$REPO" commit -qm "Add setup script, README, references and CHANGES" || true
  git -C "$REPO" push -q || echo "(push skipped - run git push yourself later)"
fi
echo "SETUP DONE"
