# Base image for the RecordingStudio Cursor Cloud Agent environment.
#
# The dummy Rails app (test/dummy) drives development and the test suite, so this
# image bakes the slow, stable system dependencies: a Ruby 3.3 toolchain, a local
# PostgreSQL server, and the libraries needed to build the pg and native gems.
# Repository-specific setup (bundle install, database, Tailwind) lives in
# .cursor/install.sh so it can see the checked-out source.
FROM ruby:3.3-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

# The official ruby image points BUNDLE_APP_CONFIG at /usr/local/bundle, which
# makes Bundler ignore each project's committed .bundle/config. Restore the
# default project-local resolution so test/dummy/.bundle/config (BUNDLE_PATH:
# vendor/bundle) is honored, matching bin/dev, bin/setup, and CI.
ENV BUNDLE_APP_CONFIG=.bundle

# Retry apt operations: the build proxy occasionally returns transient 4xx/5xx
# errors for individual package downloads.
RUN set -eux; \
    echo 'Acquire::Retries "8";' > /etc/apt/apt.conf.d/80-retries; \
    for attempt in 1 2 3 4 5; do \
      apt-get update && break || { echo "apt-get update failed (attempt ${attempt})"; sleep 5; }; \
    done; \
    for attempt in 1 2 3 4 5; do \
      apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        git \
        libffi-dev \
        libpq-dev \
        libyaml-dev \
        locales \
        nodejs \
        npm \
        pkg-config \
        postgresql \
        postgresql-client \
        procps \
      && break || { echo "apt-get install failed (attempt ${attempt})"; apt-get update || true; sleep 10; }; \
    done; \
    rm -rf /var/lib/apt/lists/*

# foreman powers `bin/dev`; bundler is pinned by the lockfiles at install time.
RUN gem install bundler foreman --no-document

# Login shells (used by the agent terminals) reset PATH via /etc/profile and drop
# the gem executables directory. Keep it on PATH so `foreman` and other global gem
# binaries stay resolvable.
RUN printf 'export PATH="/usr/local/bundle/bin:$PATH"\n' > /etc/profile.d/10-bundle-path.sh

WORKDIR /workspace
