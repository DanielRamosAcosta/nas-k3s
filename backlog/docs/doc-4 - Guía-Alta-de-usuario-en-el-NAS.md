---
id: doc-4
title: 'Guía: Alta de usuario en el NAS'
type: other
created_date: '2026-04-04 20:59'
---
## Requisitos previos

- Acceso al cluster k3s (kubectl configurado)
- Docker instalado (para generar hashes de contraseña)
- Puerto del cluster redirigido si se trabaja en remoto

## Paso 1 — Generar el hash de la contraseña

```bash
docker run --rm -it authelia/authelia:latest authelia crypto hash generate argon2
```

Esto devuelve un hash tipo `$argon2id$v=19$m=65536,t=3,p=4$...`. Cópialo.

> Para generar una contraseña aleatoria directamente:
> ```bash
> docker run --rm authelia/authelia:latest \
>   authelia crypto hash generate argon2 --random --random.length 64 --random.charset alphanumeric
> ```

## Paso 2 — Añadir el usuario al ConfigMap

Editar `lib/auth/authelia/users_database.yml` y añadir una entrada bajo `users:`:

```yaml
  nombre_usuario:
    disabled: false
    displayname: Nombre
    email: email@example.com
    family_name: Apellido
    given_name: Nombre
    groups: []          # o [admins] si es administrador
    locale: es-ES
    password: '$USER_NOMBRE_USUARIO_PASSWORD'
    picture: https://2.gravatar.com/avatar/<md5-del-email>?size=512&d=initials
    zoneinfo: Europe/Madrid
```

La convención para el placeholder es `$USER_<NOMBRE_EN_MAYUSCULAS>_PASSWORD`.

## Paso 3 — Encriptar el hash como SealedSecret

```bash
echo -n '$argon2id$v=19$m=...<hash-completo>' | ./scripts/encrypt-secret.sh auth authelia-user-passwords
```

Scope **strict** (namespace `auth`, nombre `authelia-user-passwords`).

## Paso 4 — Añadir al fichero de secrets

Editar `lib/auth/authelia/authelia.secrets.json` y añadir la entrada en el objeto `userPasswords`:

```json
{
  "userPasswords": {
    "USER_ADMIN_PASSWORD": "...",
    "USER_NOMBRE_USUARIO_PASSWORD": "<valor-encriptado-del-paso-3>"
  }
}
```

## Paso 5 — Commit, push y deploy

Seguir el flujo GitOps habitual: PR → CI verde → squash merge → ArgoCD sincroniza.

## Servicios y auto-provisioning

Una vez creado el usuario en Authelia, el comportamiento en cada servicio es:

| Servicio | Auto-provisioning | Notas |
|----------|-------------------|-------|
| **Immich** (photos) | Sí | `autoRegister: true` — el usuario se crea al hacer login por primera vez |
| **Grafana** | Sí | Auto-provisiona y asigna rol según groups: `admins` → Admin, si no → Viewer |
| **Jellyfin** (media) | No | Crear usuario manualmente desde la UI de Jellyfin |
| **SFTPGo** (cloud) | No | Crear usuario manualmente desde la UI de SFTPGo. El rol (admin/user) viene de Authelia automáticamente |
| **Booklore** (books) | No | Crear usuario manualmente desde la UI |
| **ArgoCD** | Sí | Pero solo usuarios del grupo `admins` deberían tener acceso |

## Grupos disponibles

- `admins` — acceso de administrador en Grafana, ArgoCD, y rol admin en SFTPGo
- `[]` (sin grupo) — usuario estándar, Viewer en Grafana, rol user en SFTPGo

## Notas

- El `picture` se genera con Gravatar: `https://2.gravatar.com/avatar/<md5-del-email>?size=512&d=initials`
- Para calcular el md5: `echo -n 'email@example.com' | md5`
- Los passwords se almacenan como hashes argon2id — Authelia nunca ve la contraseña en texto plano
- El ConfigMap (`users_database.yml`) es público en git; solo los hashes están encriptados como SealedSecret
