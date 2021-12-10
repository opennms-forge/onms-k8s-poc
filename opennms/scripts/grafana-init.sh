#!/bin/bash
# @author Alejandro Galue <agalue@opennms.com>

export PGHOST=${POSTGRES_HOST}
export PGPORT=${POSTGRES_PORT}
export PGUSER=${POSTGRES_USER}
export PGPASSWORD=${POSTGRES_PASSWORD}

echo "Waiting for postgresql host ${PGHOST}"
until pg_isready; do
  printf '.'
  sleep 5
done
echo "Done"

if ! psql -lqt | cut -d \| -f 1 | grep -qw "${GF_DATABASE_NAME}"; then
  echo "Creating grafana user and database on ${PGHOST}..."
  createdb -E UTF-8 "${GF_DATABASE_NAME}"
  createuser "${GF_DATABASE_USER}"
  psql -c "alter role ${GF_DATABASE_USER} with password '${GF_DATABASE_PASSWORD}';"
  psql -c "alter user ${GF_DATABASE_USER} set search_path to ${GF_DATABASE_NAME},public;"
  psql -c "grant all on database ${GF_DATABASE_NAME} to ${GF_DATABASE_USER};"
else
  TABLES=$(psql -qtAX -d "${GF_DATABASE_NAME}" -c "select count(*) from  pg_stat_user_tables;")
  echo "Grafana database already exists on ${PGHOST}."
  echo "There are ${TABLES} tables on it, skipping..."
fi
