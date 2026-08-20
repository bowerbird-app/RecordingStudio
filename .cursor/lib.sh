#!/usr/bin/env bash
# Shared helpers for the Cursor Cloud Agent environment scripts.

# Locate the repository root regardless of where the script is invoked from.
repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd
}

# Default database connection settings. These mirror test/dummy/config/database.yml
# defaults and can be overridden with environment variables if needed.
export DB_HOST="${DB_HOST:-localhost}"
export DB_PORT="${DB_PORT:-5432}"
export DB_USER="${DB_USER:-postgres}"
export DB_PASSWORD="${DB_PASSWORD:-postgres}"
export DB_NAME="${DB_NAME:-app_development}"

# Start the local PostgreSQL cluster (idempotent) and wait until it accepts
# connections. Debian ships one versioned cluster under /etc/postgresql.
start_postgres() {
  local version
  version="$(ls /etc/postgresql 2>/dev/null | sort -V | tail -1)"

  if [ -z "${version}" ]; then
    echo "No PostgreSQL cluster found under /etc/postgresql" >&2
    return 1
  fi

  pg_ctlcluster "${version}" main start 2>/dev/null || true

  for _ in $(seq 1 30); do
    if pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  echo "PostgreSQL did not become ready on ${DB_HOST}:${DB_PORT}" >&2
  return 1
}

# Ensure the postgres role has the password the dummy app expects for TCP auth.
ensure_postgres_password() {
  su - postgres -c "psql -tAc \"ALTER USER postgres PASSWORD '${DB_PASSWORD}';\"" >/dev/null
}
