#!/bin/bash

# PostgreSQL directories and ports
PG16_DATA_DIR="/var/lib/pgsql/16/data"
PG17_DATA_DIR="/var/lib/pgsql/17/data"
PG16_BIN="/usr/pgsql-16/bin"
PG17_BIN="/usr/pgsql-17/bin"
PG16_PORT=5432  # Default PostgreSQL port for 16
PG17_PORT=5433  # Temporary port for PostgreSQL 17 during migration

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root."
  exit 1
fi

echo "Step 1: Stopping PostgreSQL 16 service..."
systemctl stop postgresql-16

echo "Step 2: Initialize PostgreSQL 17 data directory if not already initialized..."
if [[ ! -f "$PG17_DATA_DIR/PG_VERSION" ]]; then
  $PG17_BIN/postgresql-17-setup initdb
else
  echo "PostgreSQL 17 data directory already initialized."
fi

echo "Step 3: Checking if PostgreSQL 16 service is down..."
if systemctl is-active --quiet postgresql-16; then
  echo "Error: PostgreSQL 16 service is still running."
  exit 1
fi

echo "Step 4: Preparing pg_upgrade..."
$PG17_BIN/pg_upgrade \
  --old-datadir="$PG16_DATA_DIR" \  # Specifies the data directory of the old PostgreSQL 16 cluster.
  --new-datadir="$PG17_DATA_DIR" \  # Specifies the data directory for the new PostgreSQL 17 cluster.
  --old-bindir="$PG16_BIN" \        # Specifies the location of PostgreSQL 16 binaries (executables like postgres, pg_ctl).
  --new-bindir="$PG17_BIN" \        # Specifies the location of PostgreSQL 17 binaries (executables).
  --old-port="$PG16_PORT" \         # The port number where the old PostgreSQL 16 instance is listening (default 5432).
  --new-port="$PG17_PORT" \         # A temporary port number for PostgreSQL 17 (5433 in this case, to avoid conflict with PostgreSQL 16).
  --jobs=$(nproc) \                 # Number of parallel jobs used for migration, based on CPU cores available.
  --link \                          # Uses hard links instead of copying files, saving disk space but preventing rollback to PostgreSQL 16.
  --verbose                         # Enables detailed logging of the upgrade process.

if [ $? -ne 0 ]; then
  echo "Error: pg_upgrade failed."
  exit 1
fi

echo "Step 5: Updating PostgreSQL 17 to listen on port 5432..."
sed -i "s/port = $PG17_PORT/port = $PG16_PORT/" "$PG17_DATA_DIR/postgresql.conf"

echo "Step 6: Starting PostgreSQL 17 service on port 5432..."
systemctl enable postgresql-17
systemctl start postgresql-17

echo "Step 7: Checking PostgreSQL 17 status..."
if systemctl is-active --quiet postgresql-17; then
  echo "PostgreSQL 17 service started successfully on port $PG16_PORT."
else
  echo "Error: PostgreSQL 17 service failed to start."
  exit 1
fi

echo "Step 8: Running post-upgrade tasks..."
$PG17_BIN/vacuumdb --all --analyze-in-stages
$PG17_BIN/reindexdb --all

echo "Step 9: Cleaning up old PostgreSQL 16 data (optional)..."
echo "Run the following command to remove old PostgreSQL 16 data after verifying the migration:"
echo "rm -rf $PG16_DATA_DIR"

echo "PostgreSQL 16 to 17 migration completed successfully!"
