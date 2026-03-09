#!/usr/bin/env bash
set -euo pipefail

echo "🏗️  Creando usuario y base de datos individual..."

# Validar variables requeridas
: "${USER_NAME:?Variable USER_NAME es requerida}"
: "${USER_PASSWORD:?Variable USER_PASSWORD es requerida}"
: "${POSTGRES_PASSWORD:?Variable POSTGRES_PASSWORD es requerida}"

# Configuración de conexión (con valores por defecto)
POSTGRES_HOST="${POSTGRES_HOST:-postgres.databases.svc.cluster.local}"
POSTGRES_PORT="5432"
POSTGRES_USER="${POSTGRES_USER:-postgres}"

echo "🔐 Creando role y BBDD para '$USER_NAME'..."

# Crear el usuario/role con LOGIN
PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$USER_NAME') THEN
        CREATE ROLE "$USER_NAME" LOGIN PASSWORD '$USER_PASSWORD';
        RAISE NOTICE 'Role % creado exitosamente', '$USER_NAME';
    ELSE
        RAISE NOTICE 'Role % ya existe', '$USER_NAME';
    END IF;
END
\$\$;
SQL

# Verificar si la base de datos ya existe y está configurada
DB_EXISTS=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -tAc "SELECT 1 FROM pg_database WHERE datname = '$USER_NAME'")

if [ "$DB_EXISTS" = "1" ]; then
    echo "✅  La base de datos '$USER_NAME' ya existe y está configurada. No se requiere ninguna acción."
    exit 0
fi

# Crear base de datos dedicada con el usuario como owner
echo "📦 Creando base de datos '$USER_NAME'..."
PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 <<SQL
CREATE DATABASE "$USER_NAME" OWNER "$USER_NAME" TEMPLATE template0;
SQL

# Revocar acceso público y dar acceso exclusivo al owner
echo "🔒 Configurando permisos exclusivos para '$USER_NAME'..."
PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 <<SQL
REVOKE CONNECT ON DATABASE "$USER_NAME" FROM PUBLIC;
GRANT  CONNECT ON DATABASE "$USER_NAME" TO "$USER_NAME";
SQL

# Revocar acceso del usuario a la base de datos "postgres" y otras bases del sistema
echo "🚫 Revocando acceso a bases de datos del sistema para '$USER_NAME'..."
PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -v ON_ERROR_STOP=1 <<SQL
REVOKE CONNECT ON DATABASE "postgres" FROM "$USER_NAME";
REVOKE CONNECT ON DATABASE "template0" FROM "$USER_NAME";
REVOKE CONNECT ON DATABASE "template1" FROM "$USER_NAME";
SQL

# Instalar extensiones útiles en la nueva base de datos
echo "🔧 Instalando extensiones en la base de datos '$USER_NAME'..."
PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$POSTGRES_HOST" -p "$POSTGRES_PORT" -U "$POSTGRES_USER" -d "$USER_NAME" -v ON_ERROR_STOP=1 <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS vchord;
CREATE EXTENSION IF NOT EXISTS cube;
CREATE EXTENSION IF NOT EXISTS earthdistance;
SQL

echo "✅  Usuario '$USER_NAME' y base de datos creados exitosamente con acceso exclusivo."
