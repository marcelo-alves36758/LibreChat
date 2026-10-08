#!/bin/sh
set -eu
cd /app
# The same .env file is loaded by the backend; process environment takes precedence.
node config/hero/validate.cjs
exec "$@"
