#!/usr/bin/env bash

set -euo pipefail

cd /workspace

export CODESPACES="${CODESPACES:-true}"
export DB_HOST="${DB_HOST:-db}"
export DB_PORT="${DB_PORT:-5432}"
export DB_USER="${DB_USER:-postgres}"
export DB_PASSWORD="${DB_PASSWORD:-postgres}"
export DB_NAME="${DB_NAME:-app_development}"
export REDIS_URL="${REDIS_URL:-redis://redis:6379/0}"

echo "==> Initializing Git LFS"
git lfs install

echo "==> Installing Node dependencies"
npm install

echo "==> Installing Playwright Chromium"
npx playwright install --with-deps chromium

echo "==> Waiting for PostgreSQL at ${DB_HOST}:${DB_PORT}"
for attempt in $(seq 1 30); do
  if pg_isready -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" >/dev/null 2>&1; then
    break
  fi

  if [ "${attempt}" -eq 30 ]; then
    echo "PostgreSQL did not become ready in time" >&2
    exit 1
  fi

  sleep 2
done

cd /workspace/test/dummy

echo "==> Installing Ruby gems"
bundle install

echo "==> Preparing database"
bundle exec rails db:prepare

echo "==> Building Tailwind CSS"
bundle exec rails tailwindcss:build
