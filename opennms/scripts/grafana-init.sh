#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>
#
# Intended to be used as part of an InitContainer expecting to run using the postgres image
#
# External environment variables used by this script:
# POSTGRES_HOST
# POSTGRES_PORT
# POSTGRES_USER
# POSTGRES_PASSWORD
# GF_DATABASE_NAME
# GF_DATABASE_USER
# GF_DATABASE_PASSWORD

export PGHOST=${POSTGRES_HOST}
export PGPORT=${POSTGRES_PORT}
export PGUSER=${POSTGRES_USER}
export PGPASSWORD=${POSTGRES_PASSWORD}

echo "Grafana Database Initialization Script..."

# Requirements
command -v pg_isready >/dev/null 2>&1 || { echo >&2 "pg_isready is required but it's not installed. Aborting."; exit 1; }
command -v psql       >/dev/null 2>&1 || { echo >&2 "psql is required but it's not installed. Aborting."; exit 1; }
command -v createdb   >/dev/null 2>&1 || { echo >&2 "createdb is required but it's not installed. Aborting."; exit 1; }
command -v createuser >/dev/null 2>&1 || { echo >&2 "createuser is required but it's not installed. Aborting."; exit 1; }

# Wait for dependencies
echo "Waiting for postgresql host ${PGHOST}"
until pg_isready; do
  printf '.'
  sleep 5
done
echo "Done"

# Create the database if it doesn't exist
if psql -lqt | cut -d \| -f 1 | grep -qw "${GF_DATABASE_NAME}"; then
  TABLES=$(psql -qtAX -d "${GF_DATABASE_NAME}" -c "select count(*) from  pg_stat_user_tables;")
  echo "Grafana database already exists on ${PGHOST}."
  echo "There are ${TABLES} tables on it, skipping..."
else
  echo "Creating grafana user and database on ${PGHOST}..."
  createdb -E UTF-8 "${GF_DATABASE_NAME}"
  createuser "${GF_DATABASE_USER}"
  psql -c "alter role ${GF_DATABASE_USER} with password '${GF_DATABASE_PASSWORD}';"
  psql -c "alter user ${GF_DATABASE_USER} set search_path to ${GF_DATABASE_NAME},public;"
  psql -c "grant all on database ${GF_DATABASE_NAME} to ${GF_DATABASE_USER};"
fi
