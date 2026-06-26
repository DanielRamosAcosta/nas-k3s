#!/bin/sh
set -eu

echo "🏗️  Aprovisionando database y usuario en CouchDB..."

# Validar variables requeridas
: "${COUCHDB_USER:?Variable COUCHDB_USER es requerida}"
: "${COUCHDB_PASSWORD:?Variable COUCHDB_PASSWORD es requerida}"
: "${USER_NAME:?Variable USER_NAME es requerida}"
: "${USER_PASSWORD:?Variable USER_PASSWORD es requerida}"
: "${DB_NAME:?Variable DB_NAME es requerida}"

COUCHDB_HOST="${COUCHDB_HOST:-http://couchdb.databases.svc.cluster.local:5984}"
AUTH="$COUCHDB_USER:$COUCHDB_PASSWORD"

# Hace una petición autenticada y devuelve solo el código HTTP por stdout.
# $1=método $2=path $3=body (opcional)
req() {
  method="$1"
  path="$2"
  body="${3:-}"
  if [ -n "$body" ]; then
    curl -s -o /dev/null -w '%{http_code}' --user "$AUTH" \
      -X "$method" "$COUCHDB_HOST$path" \
      -H 'Content-Type: application/json' -d "$body"
  else
    curl -s -o /dev/null -w '%{http_code}' --user "$AUTH" \
      -X "$method" "$COUCHDB_HOST$path"
  fi
}

# Falla solo ante errores reales (5xx o error de red). Tolera los códigos
# "ya existe" que se pasen como argumentos extra.
check() {
  code="$1"
  context="$2"
  shift 2
  for ok in 200 201 "$@"; do
    if [ "$code" = "$ok" ]; then
      return 0
    fi
  done
  echo "❌ $context falló (HTTP $code)"
  exit 1
}

# Esperar a que CouchDB esté listo (autenticado: require_valid_user=true da 401 sin auth)
echo "⏳ Esperando a CouchDB en $COUCHDB_HOST..."
RETRIES=30
until [ "$RETRIES" -eq 0 ]; do
  code=$(req GET /_up || echo 000)
  if [ "$code" = "200" ]; then
    echo "✅ CouchDB está disponible"
    break
  fi
  echo "⏳ Esperando... ($RETRIES intentos restantes, último HTTP $code)"
  RETRIES=$((RETRIES - 1))
  sleep 2
done
if [ "$RETRIES" -eq 0 ]; then
  echo "❌ CouchDB no respondió 200 en /_up tras varios intentos"
  exit 1
fi

# Crear la database (412 = ya existe)
echo "📦 Creando database '$DB_NAME'..."
code=$(req PUT "/$DB_NAME")
check "$code" "Crear database '$DB_NAME'" 412

# Crear el usuario no-admin en _users (409 = ya existe)
echo "🔐 Creando usuario '$USER_NAME' en _users..."
user_body=$(printf '{"name":"%s","password":"%s","roles":[],"type":"user"}' "$USER_NAME" "$USER_PASSWORD")
code=$(req PUT "/_users/org.couchdb.user:$USER_NAME" "$user_body")
check "$code" "Crear usuario '$USER_NAME'" 409

# Restringir el acceso a la DB solo a ese usuario (idempotente, sobrescribe).
# Member: lee/escribe docs normales. Admin local de SU base: necesario para que
# LiveSync cree design docs / índices ("Check database configuration").
echo "🔒 Configurando _security de '$DB_NAME' para '$USER_NAME'..."
sec_body=$(printf '{"admins":{"names":["%s"],"roles":[]},"members":{"names":["%s"],"roles":[]}}' "$USER_NAME" "$USER_NAME")
code=$(req PUT "/$DB_NAME/_security" "$sec_body")
check "$code" "Configurar _security de '$DB_NAME'"

echo "✅ Database '$DB_NAME' y usuario '$USER_NAME' aprovisionados correctamente."
