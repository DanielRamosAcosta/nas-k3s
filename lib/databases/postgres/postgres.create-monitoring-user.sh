#!/usr/bin/env bash
set -euo pipefail

echo "🏗️  Creando rol de monitoring, BBDD 'monitoring' y tabla backup_log..."

# Validar variables requeridas
: "${USER_PASSWORD:?Variable USER_PASSWORD es requerida}"
: "${POSTGRES_PASSWORD:?Variable POSTGRES_PASSWORD es requerida}"

# Configuración de conexión (con valores por defecto)
POSTGRES_HOST="${POSTGRES_HOST:-postgres.databases.svc.cluster.local}"
POSTGRES_PORT="5432"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

echo "🔐 Creando rol 'monitoring' y aplicando GRANT pg_monitor..."

# Rol de solo-monitoring (pg_monitor da acceso a las vistas pg_stat_* sin más privilegios).
PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'monitoring') THEN
        CREATE ROLE monitoring LOGIN PASSWORD '$USER_PASSWORD';
        RAISE NOTICE 'Rol monitoring creado exitosamente';
    ELSE
        RAISE NOTICE 'Rol monitoring ya existe';
    END IF;
END
\$\$;
GRANT pg_monitor TO monitoring;
SQL

# CREATE DATABASE no puede ir dentro de un bloque DO/transacción: usar \gexec.
echo "📦 Creando BBDD 'monitoring' (owner monitoring) si no existe..."
PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 <<SQL
SELECT 'CREATE DATABASE monitoring OWNER monitoring'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'monitoring')\gexec
SQL

# Reconectar a la BBDD 'monitoring' para crear la tabla marcador de frescura de backups.
echo "🔧 Creando tabla backup_log en la BBDD 'monitoring'..."
PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d monitoring -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE IF NOT EXISTS public.backup_log (
    db          text PRIMARY KEY,
    finished_at timestamptz NOT NULL
);
GRANT SELECT ON public.backup_log TO monitoring;
SQL

echo "✅  Rol 'monitoring', BBDD 'monitoring' y tabla backup_log listos."
