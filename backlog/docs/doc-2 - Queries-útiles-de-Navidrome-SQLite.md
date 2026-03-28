---
id: doc-2
title: Queries útiles de Navidrome (SQLite)
type: other
created_date: '2026-03-24 23:19'
updated_date: '2026-03-25 12:25'
---
# Queries útiles de Navidrome (SQLite)

La base de datos de Navidrome es SQLite y se encuentra en `/data/navidrome.db` dentro del pod `navidrome-0` (namespace `media`).

## Acceso

```bash
kubectl exec -n media navidrome-0 -- sqlite3 /data/navidrome.db "<query>"
```

## Schema de la base de datos

### Tablas principales

#### `user`
Usuarios de Navidrome.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| id | varchar(255) PK | |
| user_name | varchar(255) UNIQUE | |
| name | varchar(255) | Nombre visible |
| email | varchar(255) | |
| password | varchar(255) | Hash |
| is_admin | bool | |
| last_login_at | datetime | |
| last_access_at | datetime | |
| created_at | datetime | |
| updated_at | datetime | |

#### `artist`
Artistas musicales.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| id | varchar(255) PK | |
| name | varchar(255) | |
| biography | varchar(255) | |
| small/medium/large_image_url | varchar(255) | URLs de imágenes |
| external_url | varchar(255) | |
| order_artist_name | varchar | Para ordenar |
| sort_artist_name | varchar | Para ordenar |
| mbz_artist_id | varchar | MusicBrainz ID |
| missing | boolean | Artista sin archivos |
| similar_artists | jsonb | |
| average_rating | real | |

#### `album`
Álbumes.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| id | varchar(255) PK | |
| name | varchar(255) | |
| album_artist | varchar(255) | |
| album_artist_id | varchar(255) | FK → artist |
| min_year / max_year | int | Rango de años |
| compilation | bool | |
| song_count | integer | |
| duration | real | Segundos |
| genre | varchar(255) | |
| size | integer | Bytes |
| date / original_date / release_date | varchar(255) | |
| catalog_num | varchar | |
| mbz_album_id | varchar | MusicBrainz ID |
| mbz_album_type | varchar | (album, single, etc.) |
| discs | jsonb | Info de discos |
| library_id | integer | FK → library |
| tags | jsonb | |
| participants | jsonb | |
| explicit_status | varchar | |
| average_rating | real | |

#### `media_file`
Canciones / archivos de audio.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| id | varchar(255) PK | |
| path | varchar(255) | Ruta en disco |
| title | varchar(255) | |
| album | varchar(255) | Nombre del álbum |
| artist | varchar(255) | Nombre del artista |
| artist_id | varchar(255) | FK → artist |
| album_id | varchar(255) | FK → album |
| album_artist | varchar(255) | |
| album_artist_id | varchar(255) | FK → artist |
| track_number | integer | |
| disc_number | integer | |
| year | integer | |
| size | integer | Bytes |
| suffix | varchar(255) | Extensión (flac, mp3...) |
| duration | real | Segundos |
| bit_rate | integer | kbps |
| bit_depth | integer | |
| sample_rate | integer | Hz |
| channels | integer | |
| genre | varchar(255) | |
| compilation | bool | |
| has_cover_art | bool | |
| bpm | integer | |
| lyrics | jsonb | |
| comment | varchar | |
| mbz_recording_id | varchar | MusicBrainz ID |
| rg_album_gain/peak | real | ReplayGain álbum |
| rg_track_gain/peak | real | ReplayGain pista |
| tags | jsonb | |
| participants | jsonb | |
| library_id | integer | FK → library |
| folder_id | varchar | FK → folder |
| missing | boolean | |
| explicit_status | varchar | |
| average_rating | real | |

#### `playlist`
Playlists de usuarios.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| id | varchar(255) PK | |
| name | varchar(255) | |
| comment | varchar(255) | |
| duration | real | Duración total (seg) |
| song_count | integer | |
| public | bool | |
| owner_id | varchar(255) | FK → user |
| path | string | Ruta si importada de archivo |
| sync | bool | Sincronizar con archivo |
| size | integer | |
| rules | varchar | Reglas para smart playlists |
| evaluated_at | datetime | Última evaluación (smart) |

#### `playlist_tracks`
Relación playlist ↔ canciones.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| id | integer | Posición en la playlist |
| playlist_id | varchar(255) | FK → playlist |
| media_file_id | varchar(255) | FK → media_file |

#### `annotation`
Ratings, play counts, favoritos — por usuario y por item.

| Columna | Tipo | Descripción |
|---------|------|-------------|
| user_id | varchar(255) | FK → user |
| item_id | varchar(255) | ID del item |
| item_type | varchar(255) | `media_file`, `album`, `artist` |
| play_count | integer | |
| play_date | datetime | Última reproducción |
| rating | integer | 1-5 estrellas |
| starred | bool | Favorito |
| starred_at | datetime | |
| rated_at | datetime | |

### Tablas secundarias

| Tabla | Descripción |
|-------|-------------|
| `library` | Bibliotecas de música (rutas escaneadas) |
| `folder` | Carpetas dentro de una library |
| `tag` | Tags normalizados (genre, mood, etc.) |
| `library_tag` | Conteo de tags por library |
| `media_file_artists` | Relación media_file ↔ artist con roles |
| `album_artists` | Relación album ↔ artist con roles |
| `player` | Clientes conectados (apps Subsonic) |
| `playqueue` | Cola de reproducción por usuario |
| `radio` | Estaciones de radio |
| `share` | Links compartidos |
| `scrobble_buffer` | Buffer de scrobbles pendientes |
| `scrobbles` | Historial de scrobbles enviados |
| `bookmark` | Marcadores (posición en podcasts/audiobooks) |
| `user_props` | Preferencias de usuario (key-value) |
| `user_library` | Acceso de usuarios a libraries |
| `transcoding` | Perfiles de transcodificación |
| `property` | Propiedades del sistema |
| `plugin` | Plugins instalados |
| `playlist_fields` | Campos de playlist |

### Relaciones clave

```
user ──< annotation ──> media_file/album/artist
user ──< playlist ──< playlist_tracks >── media_file
user ──< player
user ──< scrobbles >── media_file
library ──< folder ──< media_file >── album >── artist
media_file ──< media_file_artists >── artist (con roles)
album ──< album_artists >── artist (con roles)
```

## Queries útiles

### Canciones calificadas con N estrellas por un usuario

```sql
SELECT mf.title, mf.artist, mf.album
FROM annotation a
JOIN media_file mf ON a.item_id = mf.id
JOIN user u ON a.user_id = u.id
WHERE u.user_name = 'dani'
  AND a.rating = 1;
```

- `rating`: de 1 a 5 (estrellas)
- `item_type`: `media_file` (canciones), `album` (álbumes)

### Resumen de calificaciones por usuario

```sql
SELECT u.user_name, a.item_type, a.rating, COUNT(*) as total
FROM annotation a
JOIN user u ON a.user_id = u.id
WHERE a.rating > 0
GROUP BY u.user_name, a.item_type, a.rating
ORDER BY u.user_name, a.item_type, a.rating;
```

### Playlists de un usuario con sus canciones

```sql
SELECT p.name AS playlist, mf.title, mf.artist, mf.album
FROM playlist p
JOIN playlist_tracks pt ON p.id = pt.playlist_id
JOIN media_file mf ON pt.media_file_id = mf.id
JOIN user u ON p.owner_id = u.id
WHERE u.user_name = 'dani'
ORDER BY p.name, pt.id;
```

### Top canciones más reproducidas

```sql
SELECT mf.title, mf.artist, a.play_count, a.play_date
FROM annotation a
JOIN media_file mf ON a.item_id = mf.id
JOIN user u ON a.user_id = u.id
WHERE u.user_name = 'dani'
  AND a.play_count > 0
ORDER BY a.play_count DESC
LIMIT 20;
```

### Canciones favoritas (starred)

```sql
SELECT mf.title, mf.artist, mf.album, a.starred_at
FROM annotation a
JOIN media_file mf ON a.item_id = mf.id
JOIN user u ON a.user_id = u.id
WHERE u.user_name = 'dani'
  AND a.starred = true
ORDER BY a.starred_at DESC;
```
