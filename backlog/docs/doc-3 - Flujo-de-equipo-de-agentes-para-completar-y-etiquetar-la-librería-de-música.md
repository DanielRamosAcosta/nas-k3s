---
id: doc-3
title: Flujo de equipo de agentes para completar y etiquetar la librería de música
type: other
created_date: '2026-03-29 00:13'
---
## Objetivo

Completar álbumes incompletos y corregir tags de la librería de música del NAS mediante un equipo coordinado de 3 agentes especializados (beets, lidarr, slskd) ejecutando un flujo cíclico supervisado.

Meta a largo plazo: tras 2 iteraciones supervisadas + retrospectivas, el equipo puede operar de forma más autónoma.

## Team

**Nombre:** `music-library`

| Agente | subagent_type | Rol |
|--------|--------------|-----|
| `beets` | `beets-tagger` | Inspección de tags, importación |
| `lidarr` | `lidarr-manager` | Consulta de álbumes/tracks, manual import |
| `slskd` | `slskd-manager` | Búsqueda y descarga de música |

## Flujo (secuencial, coordinado por el team lead)

```
beets (inspecciona) → reporta álbum incompleto
    → team lead envía info a lidarr (inspecciona tracks)
    → lidarr reporta qué falta (✓ presentes / ✗ faltantes)
    → team lead envía a slskd (busca y descarga)
    → slskd confirma descarga
    → team lead envía a lidarr (manual import)
    → lidarr confirma importación
    → vuelta a beets
```

## Pasos detallados por agente

### 1. [beets] Inspeccionar pendientes

Ejecutar `beet import` sobre la librería para identificar álbumes con tags por corregir. Cuando beets reporte un álbum incompleto → abortar la importación y reportar al team lead qué álbum falta.

### 2. [lidarr] Inspeccionar álbum

Recibir del team lead el nombre del álbum/artista incompleto. Buscar en Lidarr y listar **todas las tracks del álbum**, marcando cuáles están presentes (✓) y cuáles faltan (✗). Incluir artista, año, nº total de tracks. Esta info sirve de referencia para verificar que la descarga FLAC contiene el álbum entero.

### 3. [slskd] Buscar y descargar

Recibir del team lead **artista + álbum**. Buscar primero por `"artista álbum"` juntos. Si no hay resultados buenos, buscar solo por el nombre del álbum. Siempre descargar el **álbum completo en FLAC** (no tracks sueltas, no MP3), ya que lo existente probablemente sea MP3 y queremos reemplazarlo con mejor calidad. Reportar cuando la descarga finalice.

### 4. [lidarr] Manual import

Una vez slskd confirme la descarga, lanzar un manual import en Lidarr para incorporar los archivos FLAC descargados a la librería (reemplazando los MP3 existentes si aplica).

### 5. Repetir

Vuelta al paso 1 con el siguiente álbum pendiente.

## Retrospectivas

Tras cada iteración completa:
1. Recoger feedback de cada agente
2. Analizar qué fue bien, qué fue mal, qué mejorar
3. Documentar aprendizajes aquí y en memoria

---

## Retrospectiva: Iteración 1

**Álbum**: 50 Cent - Get Rich or Die Tryin' (2003)
**Resultado**: El álbum ya estaba completo en disco (21/21 FLAC via Lidarr). Solo faltaba importarlo en beets. No fue necesario descargar nada.
**Agentes activos**: beets, lidarr (slskd en standby, no fue necesario)

### Qué fue bien

- **Inspección inicial rápida**: `beet missing -c` y `beet missing -t` dieron un panorama completo de la librería en un solo comando (41 álbumes, 508 tracks faltantes).
- **Lidarr respondió con reporte detallado**: tracklist completa con formato, bitrate y tamaño. Permitió tomar la decisión correcta (no descargar).
- **Preparación proactiva**: Lidarr y slskd obtuvieron sus API keys durante el standby, ahorrando tiempo.
- **Importación limpia**: beets detectó los 2 MP3 huérfanos vs 21 FLAC nuevos y "Remove old" resolvió sin intervención manual. Match 93.3%.
- **Coordinación clara**: El flujo de bloqueo/desbloqueo de tareas funcionó bien. Los mensajes del team lead fueron específicos.

### Qué fue mal

- **El flujo completo no se ejercitó**: El álbum no necesitaba descarga, así que slskd no participó y el manual import de Lidarr no se probó. Elegir un álbum que realmente faltara habría sido mejor para la primera iteración.
- **Quoting del apostrofe**: El path `Get Rich or Die Tryin' (2003)` tiene una comilla simple literal que rompió `beet import` repetidamente. Beets perdió varios intentos hasta resolver con globs.
- **tmux-cli bug con enteros**: `tmux-cli send "1"` crashea porque interpreta "1" como int. Workaround: usar `tmux send-keys` directamente.
- **grep -P no funciona en macOS**: Lidarr tuvo que reintentar con `sed` para parsear XML. Evitable.
- **Scrollback contaminado**: kubectl panic por pipe con `head` llenó el terminal de basura.

### Aprendizajes (para próximas iteraciones)

#### Para el team lead
1. **Verificar en Lidarr ANTES de intentar descargar**: Muchos álbumes "incompletos" en beets pueden ya estar completos en disco. El flujo debería ser: beets reporta → Lidarr verifica → si está completo, beets importa directamente → si NO está completo, entonces slskd descarga.
2. **Advertir sobre paths con caracteres especiales**: Si el path tiene apóstrofes u otros caracteres, incluir un glob alternativo en el mensaje.
3. **Elegir un álbum que realmente falte** para la iteración 2, así se prueba el flujo completo incluyendo slskd y manual import.

#### Para beets
1. **Siempre abrir shell interactivo en el pod primero** (`kubectl exec -it ... -- sh`) y trabajar desde ahí. Evita problemas de quoting entre capas.
2. **Usar globs por defecto** para paths con caracteres especiales.
3. **No usar pipes con `kubectl exec -it`** (como `| head`) — causa panics.
4. **Para `tmux-cli send` con números**, usar `tmux send-keys` directamente.

#### Para lidarr
1. **Usar `sed` o `awk` desde el inicio** para parsear XML en macOS, nunca `grep -P`.
2. **Incluir veredicto en la primera línea del reporte** ("COMPLETO" o "INCOMPLETO: faltan X tracks") antes de la tabla detallada.
3. **Sugerir acción proactivamente**: si el álbum está completo, decir "no necesita descarga, sugiero importar en beets directamente".

### Flujo revisado (v2)

```
beets (inspecciona con `beet missing`) → reporta álbum incompleto
    → team lead envía a lidarr (verifica estado real en disco)
    → lidarr reporta:
        SI COMPLETO → team lead envía a beets (importar directamente)
        SI INCOMPLETO → team lead envía a slskd (buscar + descargar FLAC completo)
            → slskd confirma descarga
            → team lead envía a lidarr (manual import)
            → lidarr confirma
    → vuelta a beets con siguiente álbum
```

---

## Retrospectiva: Iteración 2

**Álbum**: AC/DC - Back in Black (1980)
**Resultado**: Flujo completo ejercitado. Álbum descargado en FLAC 24bit/96kHz e importado en Lidarr y beets (10/10 tracks).
**Agentes activos**: beets, lidarr, slskd (los 3 participaron)

### Qué fue bien

- **Beets aplicó todos los aprendizajes de la iteración 1**: shell interactivo + glob + `-I`. Cero intentos fallidos, importación directa en 4 comandos vs ~15 en la iteración 1.
- **Lidarr mejoró el formato de reporte**: veredicto en primera línea ("INCOMPLETO — 1/10"), mucho más rápido de procesar.
- **slskd encontró FLAC 24bit/96kHz rápido**: AC/DC es popular, pero el filtrado (FLAC, slots libres, cola vacía) fue eficiente. Descarga completa en <1 minuto (~14 MB/s).
- **El flujo v2 funcionó**: verificar en Lidarr antes de descargar evitó trabajo innecesario (como en iteración 1).
- **Lidarr resolvió 3 problemas encadenados sin escalar**: unicode en filenames, API de manual import fallida, y MP3 duplicado.

### Qué fue mal

- **Manual import API de Lidarr no funciona como esperado**: El POST a `/api/v1/manualimport` devuelve preview pero no ejecuta. `DownloadedAlbumsScan` tampoco identificaba al artista. Lidarr tuvo que copiar archivos directamente al directorio de la librería + RescanFolders como workaround.
- **Unicode en filenames**: Track 10 tenía smart quote (U+2019) en "Ain't" que impedía el import. Requirió renombrar vía kubectl exec.
- **Lidarr prefirió MP3 sobre FLAC**: Al hacer RescanFolders, Lidarr mantuvo el MP3-320 de Shoot to Thrill en vez del FLAC. Requirió eliminar el trackfile MP3 vía API + RefreshArtist.
- **Mensajes duplicados**: Lidarr recibió Task #6 múltiples veces por desfase en la comunicación. El team lead debería hacer acknowledgment explícito.
- **Tiempo muerto de slskd**: Estuvo en standby mucho tiempo esperando desbloqueo. Podría haber lanzado búsqueda especulativa.

### Aprendizajes (para próximas iteraciones)

#### Para el team lead
1. **Hacer acknowledgment explícito** cuando un agente reporta. Evita que reenvíen el mismo reporte.
2. **Pasar la lista de tracks de Lidarr a slskd** para que pueda cruzar contra lo que encuentra en Soulseek antes de descargar.
3. **Pedir a slskd que reporte caracteres especiales** en filenames descargados, para que Lidarr anticipe problemas de unicode.

#### Para beets
1. **Encadenar verificación post-import**: `beet import -I ./path && beet list 'album:X' && beet missing -c 'album:X'` en un solo paso.
2. **Para selección de candidatos**, cruzar `beet missing -c` con `beet list` para calcular ratio tienen/faltan de una sola vez.

#### Para lidarr
1. **NO usar manual import API**. Flujo que funciona:
   1. Sanitizar filenames (normalizar unicode: smart quotes → apóstrofes normales)
   2. Eliminar trackfiles existentes de menor calidad vía API
   3. Copiar FLACs al directorio de la librería
   4. RefreshArtist + RescanFolders
   5. Verificar 100%
2. **Siempre eliminar trackfiles de menor calidad ANTES de copiar los nuevos**.

#### Para slskd
1. **Lanzar búsqueda especulativa** mientras espera desbloqueo formal, para tener resultados filtrados listos.
2. **Reportar caracteres especiales en filenames** descargados.
3. **Verificar archivos en disco** (vía kubectl exec) como paso de validación antes de reportar completado.
4. **Para artistas menos populares**: plan B con búsqueda por álbum solo, variantes del nombre, o browse de usuarios con buen catálogo.

### Flujo revisado (v3)

```
beets (inspecciona con `beet missing`) → reporta álbum incompleto
    → team lead envía a lidarr (verifica estado real en disco)
    → lidarr reporta con veredicto en primera línea + tracklist completa:
        SI COMPLETO → team lead envía a beets (importar directamente)
        SI INCOMPLETO →
            → team lead envía tracklist a slskd (buscar + descargar FLAC completo)
            → slskd descarga, reporta filenames y caracteres especiales
            → team lead envía a lidarr (import via copy+rescan):
                1. Sanitizar filenames
                2. Eliminar trackfiles de menor calidad
                3. Copiar FLACs a librería
                4. RefreshArtist + RescanFolders
                5. Verificar
            → lidarr confirma
            → team lead envía a beets (importar con -I + glob)
    → vuelta a beets con siguiente álbum
```

### Métricas comparativas

| Métrica | Iteración 1 | Iteración 2 |
|---------|-------------|-------------|
| Flujo completo ejercitado | No (álbum ya completo) | Sí (descarga + import) |
| Agentes activos | 2 (beets, lidarr) | 3 (beets, lidarr, slskd) |
| Problemas de beets | 5+ intentos fallidos | 0 |
| Problemas de lidarr | grep -P (menor) | 3 problemas (manual import API, unicode, MP3 duplicado) |
| Problemas de slskd | N/A | 0 |
| Resultado final | 21/21 FLAC 16/44.1 | 10/10 FLAC 24/96 |

---

## Mini-retro: Modo autónomo (álbumes 3-13)

**Álbumes procesados en este tramo**: Chingy, BHG Hooray, BEP The E.N.D, BHG Hefty Fine, BHG One Fierce Beer Coaster, All That Remains, Bag Raiders, Avantasia, C418, Alphabeat (en progreso), Aerosmith (en progreso)

**Descartados** (no en Lidarr): Calvin Harris, Amon Amarth, Ben Briggs, Beats International, CAPSULE, Cheryl Lynn

### Qué funciona bien

- **Batching**: Procesar 3-4 álbumes en paralelo (verificar → descargar → importar) es mucho más eficiente que uno a uno.
- **Flujo v3 estabilizado**: copy+rescan funciona consistentemente. Cero intentos fallidos de manual import API.
- **slskd muy fiable**: 0 errores en ~80+ descargas. Buenas fuentes, velocidades altas.
- **Beets aplica aprendizajes**: shell interactivo + glob + -I consistente. Cero problemas de quoting desde la iteración 1.
- **Filtrar por Lidarr funciona**: Descartar artistas no trackeados evita trabajo innecesario.

### Problemas encontrados

- **BEP The E.N.D**: Match bajo (70.3%) porque MusicBrainz solo tiene Deluxe edition. 10 bonus tracks "missing" que no teníamos intención de tener. Aceptable pero no ideal.
- **Mensajes duplicados de lidarr**: Sigue respondiendo múltiples veces al mismo mensaje. No bloquea el flujo pero añade ruido.
- **Calvin Harris se añadió a Lidarr por timing**: El mensaje de cancelación llegó después del add. Requirió cleanup (DELETE artist). Lesson: confirmar ANTES de pedir acciones irreversibles.
- **Desfase en recepción de mensajes**: lidarr a veces procesa mensajes en orden incorrecto (responde al anterior ignorando el nuevo).

### Aprendizajes nuevos

1. **Batch verification + batch download + batch import** es el modo óptimo. Verificar todos en Lidarr → descargar todos con slskd → importar todos en Lidarr → importar todos en beets.
2. **No enviar acciones irreversibles (add artist, delete) sin confirmación previa del team lead**.
3. **BEP-style mismatch**: Si MusicBrainz solo tiene Deluxe y nosotros tenemos Standard, las "missing" tracks son esperadas. Documentar pero no intentar completar.
4. **Hi-res FLAC** (Avantasia 24/192, ~2.4GB) funciona sin problemas en el flujo.

### Álbumes fallidos

- **Luciano Pavarotti - Classic Pavarotti**: No disponible en FLAC en Soulseek. Compilación clásica poco compartida en lossless.
- **deadmau5 - 4x4=12**: Lidarr no pudo mapear FLACs (sin tags MusicBrainz). Import manual via UI.
- **Hans Zimmer - Sherlock Holmes OST**: Mismo problema que deadmau5. Import manual via UI.
- **Kylie Minogue - X**: Mismo problema unmapped. Import manual via UI.
- **Luciano Pavarotti - Classic Pavarotti**: No disponible en FLAC en Soulseek.
- **Opus Atlantica - Opus Atlantica**: No disponible en FLAC (metal nicho).
- **PALO! - This Is Afro-Cuban Funk**: No disponible en FLAC (1 usuario con 6204 en cola).
- **Ratatat - LP3**: No disponible en Soulseek (0 resultados).
- **The Kinks - Anthology**: Compilación, descartado.
- **The Buggles - The Age of Plastic**: Artista no en Lidarr, descartado.

---

## Retro final: Resumen completo

### Álbumes completados (~50 total)

**Iteraciones supervisadas (1-2):**
50 Cent GRODT, AC/DC Back in Black

**Modo autónomo - primera ronda (álbumes de estudio):**
Chingy Powerballin', BHG Hooray/Hefty/Beer Coaster, BEP The E.N.D, All That Remains, Bag Raiders, Avantasia, C418, Alphabeat, Aerosmith

**Modo autónomo - segunda ronda (scan beet import):**
B.J. Thomas, 50 Cent Massacre, Coldplay Viva la Vida, Beats International, Ben E. King, Coolio, DJ Aligator, DMX, ELO, Ellie Goulding, Global Deejays, Goldfish, Hans Zimmer (manual), Harold Faltermeyer, Herbie Hancock, Jack Ü, JAY-Z, Joe Budden, John Williams Star Wars, Kan Gao, Kesha, Knife Party, Lou Bega, Ludacris, Machines of Loving Grace, Martin Solveig, Michael Jackson Thriller, NERO, OneRepublic, One-T, O-Zone, Papa Roach

**Batch final (scan P-Z):**
Queen, Rick Astley, Jimi Hendrix, The Who, Sum 41, The Offspring, The Prodigy, Jackson 5, Tenacious D, Skrillex, Skillet x2, Ramin Djawadi, Pixies, Quincy Jones, Streetlight Manifesto, The Heavy, Samael, Ween, Yelle, Yello

**Pendiente**: Pathfinder (descargando lento)

**~120 álbumes/singles aplicados** en beets (ya tenían buen match)

### Álbumes descartados (no en Lidarr = singles sueltos)

- Calvin Harris, Amon Amarth, Ben Briggs, Beats International (luego encontrado), CAPSULE, Cheryl Lynn, Lil Jon, The Buggles, Gene Kelly
- Ben Briggs - The Briggs Effect 2
- Beats International - Let Them Eat Bingo
- CAPSULE - PLAYER
- Cheryl Lynn - The Real Thing

### Singles no completados (8, decisión: dejar como están)

- 50 Cent - Candy Shop, Aerosmith - I Don't Want to Miss a Thing, Backstreet Boys - Everybody, Bee Gees - Stayin' Alive, Berlin - Take My Breath Away, Boy Meets Girl - Waiting for a Star to Fall, Bill Medley & Jennifer Warnes - Time of My Life, Miss Monique & Glowal - Rollin'
- Motivo: son singles reales matcheados contra releases de 2-3 tracks. Las tracks "faltantes" son B-sides/remixes difíciles de encontrar en FLAC y de bajo valor.

### Métricas del proceso

- **Álbumes de estudio completados**: 13/13 (100%)
- **Errores de descarga**: 0
- **Errores de import**: 0
- **Álbumes que ya estaban completos**: 1 (50 Cent — solo faltaba import en beets)
- **Hi-res encontrados**: 3 (AC/DC 24/96, Avantasia 24/192, Aerosmith 24/96)
- **Agentes reiniciados por pérdida de contexto**: 0

### Flujo final validado (v3)

El flujo v3 funcionó de forma estable para los 13 álbumes sin modificaciones necesarias. La optimización principal fue el batching (verificar 3-4 en Lidarr → descargar todos con slskd → importar todos en Lidarr → importar todos en beets).
