---
name: task-format
description: Formato markdown de un archivo de tarea de Backlog.md (nombre de archivo, frontmatter YAML y secciones con marcadores HTML — Description, Implementation Plan, Implementation Notes, Acceptance Criteria, Definition of Done). INVÓCALA con la herramienta Skill —no basta con leer el SKILL.md a mano ni con grep— SIEMPRE antes de leer, escribir, editar o mover a mano cualquier sección, marcador o frontmatter de un archivo en backlog/tasks/ (p. ej. insertar el Implementation Plan, añadir Implementation Notes, marcar un AC/DoD, tocar el frontmatter). Es un paso obligatorio aunque creas que solo necesitas un detalle suelto. Única excepción: no hace falta al crear una tarea nueva con el MCP de backlog.
---

# task-format — formato de archivo de Backlog.md

Referencia del formato de un archivo de tarea de Backlog.md. Las tareas viven en `backlog/tasks/` como archivos markdown con frontmatter YAML + secciones delimitadas por marcadores HTML.

## Nombre de archivo

```
backlog/tasks/nasks-<N> - <Titulo-con-guiones>.md
```

- `<N>`: número del ID, sin el prefijo `NASKS` (p.ej. `69`).
- El título va con **espacios reemplazados por guiones**; se conservan acentos y ñ.
- Quita del nombre de archivo la puntuación problemática (`:`, `/`, `?`, …). El título completo y real va en el frontmatter.
- Prefijo del proyecto: `NASKS` (definido en `backlog/config.yml`).

## Frontmatter (YAML)

```yaml
---
id: NASKS-69
title: Titulo de la tarea
status: To Do
assignee:
  - Daniel
created_date: '2026-06-25 19:51'
updated_date: '2026-06-25 21:48'
labels:
  - obsidian
  - markdown
dependencies:
  - NASKS-1
references:
  - 'https://www.eferro.net/2024/12/using-blameless-incident-management-to.html'
priority: medium
ordinal: 67000
---
```

| Campo | Tipo | Notas |
|---|---|---|
| `id` | string | `NASKS-<N>`, con prefijo en mayúsculas. Lo asigna Backlog. |
| `title` | string | Título completo. Si es largo, YAML lo puede plegar con `>-` en varias líneas. |
| `status` | enum | `Draft`, `To Do`, `In Progress`, `Done` (ver `config.yml`). |
| `assignee` | lista | Lista de personas (puede ir vacía: `[]`). |
| `created_date` | string | `'yyyy-mm-dd HH:MM'`, entre comillas simples. |
| `updated_date` | string | `'yyyy-mm-dd HH:MM'`. Aparece cuando la tarea se ha modificado. |
| `labels` | lista | Etiquetas de clasificación. |
| `dependencies` | lista | IDs de tareas de las que depende (p.ej. `NASKS-1`). |
| `references` | lista | URLs o rutas de archivo de contexto. URLs entre comillas simples. |
| `documentation` | lista | (opcional) URLs/rutas de docs de diseño, specs, manuales. |
| `parentTaskId` | string | (opcional) ID del padre si es una subtarea. |
| `milestone` | string | (opcional) Hito asociado. |
| `priority` | enum | `high`, `medium`, `low`. |
| `ordinal` | número | Orden manual. Espaciado de 1000 en 1000 para dejar hueco a inserciones. |

## Secciones del cuerpo

Cada sección lleva un encabezado `##` y un par de marcadores HTML `BEGIN`/`END`. **Los marcadores son obligatorios y exactos** — Backlog parsea cada sección por ellos. El contenido va entre el `BEGIN` y el `END`.

### Description

```markdown
## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Este es el cuerpo
<!-- SECTION:DESCRIPTION:END -->
```

### Acceptance Criteria

Lista de criterios numerados `#1`, `#2`, … con casilla `- [ ]` (pendiente) o `- [x]` (cumplido). El marcador NO lleva prefijo `SECTION:`.

```markdown
## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Esto es un criterio
- [x] #2 Esto es otro criterio
<!-- AC:END -->
```

### Implementation Plan

```markdown
## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Este es el cuerpo del implementation plan
<!-- SECTION:PLAN:END -->
```

### Implementation Notes

```markdown
## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Estas son las implementation notes
<!-- SECTION:NOTES:END -->
```

### Comments

Cada comentario es un bloque con `author:` y `created:`, seguido de `---`, el cuerpo, y otro `---` de cierre. Los bloques se separan entre sí por una línea en blanco.

```markdown
## Comments

<!-- COMMENTS:BEGIN -->
author: Daniel
created: 2026-06-25 21:47
---
Esto es el primer comentario
---

author: Daniel
created: 2026-06-25 21:47
---
Esto es otro comentario
---
<!-- COMMENTS:END -->
```

### Definition of Done

Misma forma que Acceptance Criteria (numerada con casillas), marcador `DOD` sin prefijo `SECTION:`.

```markdown
## Definition of Done
<!-- DOD:BEGIN -->
- [ ] #1 Este es un criterio de done
- [ ] #2 Este es otro criterio de done
<!-- DOD:END -->
```

## Resumen de marcadores

| Sección | Encabezado | Marcador |
|---|---|---|
| Description | `## Description` | `SECTION:DESCRIPTION:BEGIN` / `:END` |
| Acceptance Criteria | `## Acceptance Criteria` | `AC:BEGIN` / `AC:END` |
| Implementation Plan | `## Implementation Plan` | `SECTION:PLAN:BEGIN` / `:END` |
| Implementation Notes | `## Implementation Notes` | `SECTION:NOTES:BEGIN` / `:END` |
| Comments | `## Comments` | `COMMENTS:BEGIN` / `COMMENTS:END` |
| Definition of Done | `## Definition of Done` | `DOD:BEGIN` / `DOD:END` |

## Significado de cada sección (convención del proyecto)

- **Description** = el **WHY**: resultado deseado y contexto de handoff. Sin pasos de implementación.
- **Acceptance Criteria** = el **WHAT**: criterios atómicos, testeables e independientes (incluyen tests y docs esperados).
- **Implementation Plan** = el **HOW**: se rellena al empezar a ejecutar.
- **Implementation Notes** = qué se hizo realmente: se rellena al terminar.
- **Definition of Done** ≠ AC: AC define scope/comportamiento del producto; DoD define hygiene de cierre (lint, tests verdes, docs).
