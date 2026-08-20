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

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
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
 && rm -rf /var/lib/apt/lists/*

# foreman powers `bin/dev`; bundler is pinned by the lockfiles at install time.
RUN gem install bundler foreman --no-document

WORKDIR /workspace
