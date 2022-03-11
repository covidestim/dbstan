#!/usr/bin/bash

docker run \
  --rm \
  -e POSTGRES_PASSWORD=password \
  -p 5432:5432 \
  --mount type=bind,source="$(pwd)/init.sql",target="/docker-entrypoint-initdb.d/init.sql" \
  postgres
