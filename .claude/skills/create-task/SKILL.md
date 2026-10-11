---
name: create-task
description: Explica cómo crear tareas en el vault de Obsidian (docs/nas-k3s/Tasks/). Usar cuando se ordene crear una tarea nueva.
---

# create-task — crear una tarea en el vault de Obsidian

Las tareas son notas markdown en `docs/nas-k3s/Tasks/`, visualizadas con la Base `Tasks.base` (kanban por `status`). Se crean a partir de la plantilla `Task` vía el **CLI de Obsidian** — nunca a mano ni con un MCP de backlog (ya no existe).

## 1. Acordar los criterios de aceptación

Primero, decide qué Acceptance Criteria debe tener la tarea en base a la conversación mantenida. Transmíteselos al usuario y pídele que los confirme. Si has hecho análisis con el usuario, deja todo documentado al rellenar la tarea.

## 2. Crear la nota desde la plantilla

```bash
obsidian create name="<título>" path="Tasks/<título>.md" template="Task" vault="nas-k3s"
```

- El CLI resuelve `{{title}}` y `{{date}}` y aplica la plantilla `Task`.
- Usa un `<título>` sin puntuación problemática en el nombre de fichero (`:` `/` `\` `?` `*` `"` `<` `>` `|`); el título real queda igualmente en la propiedad `title`.

## 3. Rellenar la nota creada

- **Description** (ya trae los sub-encabezados):
  - 📌 TLDR — resumen breve, 1–3 frases.
  - 🎯 Contexto funcional — qué hace la tarea y por qué es necesaria.
  - ⚙️ Contexto técnico — cómo se implementará, qué servicios/APIs/librerías, qué endpoints o métricas se tocan.
- **status**: `To Do` (ya por defecto).
- **priority**: `1` (alta), `2` (media) o `3` (baja) — decide la criticidad según lo hablado.
- **labels**: etiquetas de clasificación.
- **references**: enlaces a investigación/documentación/pruebas ya realizadas.
- **parent** / **dependencies**: si aplica, como wikilinks (`"[[Otra tarea]]"`).
- **Acceptance Criteria**: los criterios confirmados, en alto nivel (`- [ ] #1 ...`).

## Qué NO hacer al crear

- **No rellenes `## Implementation Plan` ni `## Implementation Notes`** — se completan más adelante (Plan al empezar a ejecutar, Notes al terminar). Deja esas secciones vacías.
- Si la tarea es para **crear un servicio nuevo**, añade una sección `## Definition of Done` con `- [ ] #1 desplegar con /deploy`. No lo pongas como Acceptance Criterion.
