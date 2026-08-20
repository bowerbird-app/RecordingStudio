#!/usr/bin/env bash
# Per-boot initialization for the Cursor Cloud Agent environment.
#
# Runs every time the environment starts. Keep it lightweight: bring up the
# database service so the Rails server (started in the `rails-dev` terminal) can
# connect. Dependency installation and schema/asset generation live in
# .cursor/install.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.cursor/lib.sh
source "${SCRIPT_DIR}/lib.sh"

echo "==> Starting PostgreSQL"
start_postgres
echo "==> PostgreSQL is ready on ${DB_HOST}:${DB_PORT}"
