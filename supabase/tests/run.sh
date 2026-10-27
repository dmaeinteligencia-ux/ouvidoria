#!/usr/bin/env bash
# Aplica as migrações num banco descartável e roda os testes de regras.
# Uso: DATABASE_URL=postgres://... npm run test:db   (o banco é apagado e recriado)
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DATABASE_URL:?defina DATABASE_URL apontando para um Postgres de teste}"
psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -c 'drop schema if exists public cascade; drop schema if exists auth cascade; create schema public;'
psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f tests/auth_stub.sql
for f in migrations/*.sql; do
  psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f "$f"
done
for f in tests/*_test.sql; do
  echo "== $f"
  psql "$DATABASE_URL" -q -v ON_ERROR_STOP=1 -f "$f"
done
echo "Todos os testes passaram."
