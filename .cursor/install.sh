#!/usr/bin/env bash
# Repository bootstrap for the Cursor Cloud Agent environment.
#
# Runs after the source is checked out (and once, at build time, when the
# environment is built into a snapshot). Must be idempotent.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.cursor/lib.sh
source "${SCRIPT_DIR}/lib.sh"

ROOT="$(repo_root)"
cd "${ROOT}"

export DUMMY_SEED_PASSWORD="${DUMMY_SEED_PASSWORD:-password}"

echo "==> Starting PostgreSQL"
start_postgres
ensure_postgres_password

echo "==> Installing gem (root) dependencies"
bundle install

echo "==> Installing dummy app dependencies"
cd "${ROOT}/test/dummy"
export BUNDLE_PATH=vendor/bundle
bundle install

echo "==> Preparing the development and test databases"
bin/rails db:prepare

echo "==> Building Tailwind CSS"
bundle exec rails tailwindcss:build

echo "==> Seeding development data"
bin/rails db:seed

echo "==> Install complete"
echo "    Sign-in accounts: admin@example.com / avery@example.com / quinn@example.com"
echo "    Seed password: ${DUMMY_SEED_PASSWORD}"
