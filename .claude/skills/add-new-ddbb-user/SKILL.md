---
name: add-new-ddbb-user
description: Add a new Postgres logical database + user to the shared cluster Postgres. Use when the user wants to onboard a new app that needs its own database, or asks to create a DB/user for a service.
---

# /add-new-ddbb-user

Añadir un nuevo usuario y base de datos lógica al Postgres compartido del clúster. Sigue todos los pasos en orden.

El usuario te debe haber dicho el nombre de la app (se usa como nombre de usuario y de base de datos). Si no lo ha dicho, pregúntalo antes de empezar.

## Paso 1 — Generar contraseña y cifrar en un solo pipeline

**Nunca imprimas ni captures la contraseña en claro — ni en stdout, ni en el contexto de Claude.**

Genera, cifra y borra en un único pipeline:

```bash
openssl rand -hex 32 > /tmp/dbpass.txt && \
  cat /tmp/dbpass.txt | ./scripts/encrypt-secret.sh --cluster-wide && \
  rm -f /tmp/dbpass.txt
```

Solo el valor cifrado (`AgC...`) aparece en stdout. Ese es el valor a guardar.

## Paso 3 — Añadir al secrets file

Edita `lib/databases/postgres/postgres.secrets.json`.

Añade una nueva entrada al final del objeto JSON, siguiendo el patrón `userNombreApp`:

```json
{
  ...,
  "userNombreApp": "<valor-cifrado-AgC...>"
}
```

## Paso 4 — Registrar en postgres.libsonnet

Edita `lib/databases/postgres/postgres.libsonnet`.

Añade una línea junto a los demás `userXxx`, en la sección `new()::`:

```jsonnet
userNombreApp: self.createUser('nombreapp', secrets.userNombreApp, self.createUserMigration, self.sealedSecret),
```

El primer argumento es el nombre del rol y la base de datos que se crearán en Postgres.

## Paso 5 — Validar compilación

```bash
tk eval environments/databases 2>&1 | tail -5
```

Debe terminar sin errores (última línea: `}`). Si falla, corrige el JSON/Jsonnet antes de continuar.

## Notas sobre el script de creación

El script `lib/databases/postgres/postgres.create-user.sh` crea el rol, la base de datos y configura permisos de forma idempotente:
- Si el rol ya existe, no lo toca.
- Si la base de datos ya existe, sale sin hacer nada más.
- La DB se crea con `ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C' TEMPLATE template0` — configuración correcta para cualquier app.

El Job se ejecutará automáticamente cuando ArgoCD sincronice el entorno `databases`.

## Resultado esperado

Cuando ArgoCD sincronice, el Job `postgres-create-user-<nombreapp>` correrá y dejará el rol y la base de datos listos en Postgres. La contraseña en texto plano se pasa al app vía SealedSecret cluster-wide, referenciado desde el libsonnet del app.
