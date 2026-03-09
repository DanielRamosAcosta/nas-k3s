#!/usr/bin/env bash
set -euo pipefail

echo "🏗️  Creando usuario y base de datos en MariaDB..."

# Validar variables requeridas
: "${USER_NAME:?Variable USER_NAME es requerida}"
: "${USER_PASSWORD:?Variable USER_PASSWORD es requerida}"
: "${MYSQL_ROOT_PASSWORD:?Variable MYSQL_ROOT_PASSWORD es requerida}"

# Configuración de conexión (con valores por defecto)
MYSQL_HOST="${MYSQL_HOST:-mariadb.databases.svc.cluster.local}"
MYSQL_PORT="3306"
MYSQL_USER="${MYSQL_USER:-root}"

echo "⏳ Esperando que MariaDB esté disponible en $MYSQL_HOST:$MYSQL_PORT..."

# Esperar a que MariaDB esté listo
RETRIES=30
WAIT=2
until [ $RETRIES -eq 0 ]; do
    if mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" &>/dev/null; then
        echo "✅ MariaDB está disponible"
        break
    fi
    echo "⏳ Esperando... ($RETRIES intentos restantes)"
    RETRIES=$((RETRIES - 1))
    sleep $WAIT
done

if [ $RETRIES -eq 0 ]; then
    echo "❌ MariaDB no está disponible después de varios intentos"
    exit 1
fi

echo "🔐 Creando base de datos y usuario para '$USER_NAME'..."

# Crear base de datos y usuario
mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" -p"$MYSQL_ROOT_PASSWORD" <<SQL
CREATE DATABASE IF NOT EXISTS \`${USER_NAME}\`;
CREATE USER IF NOT EXISTS '${USER_NAME}'@'%' IDENTIFIED BY '${USER_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${USER_NAME}\`.* TO '${USER_NAME}'@'%';
FLUSH PRIVILEGES;
SQL

echo "✅ Usuario '$USER_NAME' y base de datos creados exitosamente."
