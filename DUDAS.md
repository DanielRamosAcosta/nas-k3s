# Dudas de identificación TMDB — DVDs

Registro de las entradas de `_dvds_100.json` / `_dvds_incompletos.json` cuyo `tmdbId`
no es concluyente. Metodología: título + etiqueta de volumen del disco (`nombre_real`);
para las ambiguas, extracción de frames del rip (VIDEO_TS) e identificación visual.

## Sin `tmdbId` (null) — no mapean a una única entrada de TMDB

Estas 5 no tienen un ID porque no son "una película" en el sentido de TMDB.

### 1. `_dvds_100.json[9]` — «Diviértete con el Inglés / Pato aventuras» (carpeta `DIBUJOS`)
- **Recopilatorio de dibujos**, no una película. Frames: cortos clásicos Disney (Goofy)
  mezclados con material educativo de inglés y «Patoaventuras» (DuckTales).
- Sin título único en TMDB. Referencia parcial: DuckTales = `tv/720`.

### 2. `_dvds_100.json[23]` — «Hotwheels Acceleracers / My Scene» (carpeta con `VIDEO_TS`)
- **Disco con dos marcas Mattel distintas.** Frames confirman: título 1 = Hot Wheels
  AcceleRacers (CGI), título 2 = muñecas My Scene.
- Candidatos: serie AcceleRacers `tv/6029`; pelis AcceleRacers (Ignition `movie/72720`,
  Speed of Silence `39811`, Breaking Point `39810`, Ultimate Race `66587`);
  My Scene Goes Hollywood `movie/103434`. No hay un ID único válido.

### 3. `_dvds_100.json[40]` — «Para Daniel con cariño de Victoria» (carpeta `11 jun 2007`)
- **Vídeo casero personal** (la etiqueta del disco es una fecha, no un título).
- No existe en TMDB y no se recuperó (no hay carpeta en el NAS). Sin ID posible.

### 4. `_dvds_incompletos.json[11]` — «Pericio Ripiao / Vampiros en la habana» (carpeta `Pericio Ripiao`)
- **Recopilatorio de dos películas** (el rip tiene dos títulos VTS distintos). Frames:
  título 1 = acción real (comedia dominicana), título 2 = animación con logo «TVE 2»
  (grabación de televisión de la peli cubana).
- Candidatos: «Perico Ripiao» (2003) = `movie/25000`; «¡Vampiros en La Habana!» (1985)
  = `movie/90063`. Si hay que asignar uno, el principal sería Perico Ripiao (`25000`).

### 5. `_dvds_incompletos.json[81]` — «The Yellowjackets 25»
- **Irresoluble.** Sin pista en la etiqueta de disco, no se recuperó (no hay carpeta).
  El único «Yellowjackets» conocido es la serie de 2021 (`tv/117488`), incompatible con
  la época de la colección (~2000-2009). Probable ripeo mal etiquetado. Sin ID fiable.

## Con `tmdbId` pero confianza media (revisar si se quiere certeza)

Verificadas por frame y **confirmadas** (ya de alta confianza, se dejan anotadas por el cambio):
- `100[8]` Desaparecida → **Flightplan (2005)** `9315`. Corrección: NO es «The Missing».
  El código de disco `FLT0EUW1` (FLT = Flight) y el frame (entorno moderno) lo confirman.
  Título de estreno en España: «Plan de vuelo: Desaparecida».
- `100[14]` El Jefe → **The Man (2005)** `9074`. Frame: Eugene Levy + Samuel L. Jackson.
- `incompletos[9]` Secretos de familia → **Keeping Mum (2005)** `9687`. Frame: el arcón con
  cerraduras, el pueblo y la vicaría (era null, ahora identificada).
- `incompletos[37]` Feliz navidad → **Joyeux Noël (2005)** `11661`. Frame: oficial francés
  con uniforme de la 1ª GM en escena navideña nocturna (tregua de Navidad).
- `incompletos[54]` Alejandro Magno → **Alexander (2004)** `1966`. Frame: Colin Farrell rubio.

Confianza media **sin** verificación visual (sin frame; conviene una segunda mirada):
- `100[1]` Arthur → Arthur and the Invisibles (2006) `9992` — etiqueta de una sola palabra.
- `incompletos[2]` Toy Story → `862` — el código de disco no distingue de Toy Story 2 (`863`).
- `incompletos[12]` Bob Esponja → serie `tv/387` — el disco no distingue serie vs película (2004).
- `incompletos[14]` El Inquisidor → Day of Wrath (2006) `16432` — descartado telefilme homónimo.
- `incompletos[25]` Los Lunnies En la Tierra de los Cuentos → serie `tv/100686` — el DVD es un
  recopilatorio/especial sin ficha propia; se apunta a la serie.
- `incompletos[83]` El corral → Barnyard (2006) `9907` — no recuperado (sin carpeta), sin verificar.
  (Corregido: el `30061` que se asignó primero era «Justice League: Crisis on Two Earths».)
- `incompletos[87]` Pinocho → clásico Disney 1940 `10895` — asumido; sin carpeta para verificar versión.
