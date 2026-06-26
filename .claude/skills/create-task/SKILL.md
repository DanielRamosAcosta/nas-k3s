---
name: create-task
description: Explica cómo crear tareas en el backlog. Usar cuando se ordene crear una tarea nueva.
---

# create-task — crear una tarea en el backlog

Primero, decide qué criterios de aceptación debe tener la tarea en base a la conversación mantenida. Transmíteselas al usuario y pídele que las confirme. Una vez confirmadas, crea la tarea en el backlog con la información que te proporcione el usuario.

Si has hecho un análisis de la tarea con el usuario, deja todo documentado al crear la tarea.

Crea la tarea con:

* Título: nombre relevante y descriptivo, 1–200 caracteres.
* Descripción: explicación detallada de la tarea, con los siguientes títulos de sección:
  * 📌 TLDR — resumen breve de la tarea, 1–3 frases.
  * 🎯 Contexto funcional — qué hace la tarea y por qué es necesaria.
  * ⚙️ Contexto técnico — cómo se implementará la tarea, qué servicios, APIs o librerías se usarán, qué endpoints o métricas se tocarán, etc.
* Status: `To Do`
* Priority: Decide la criticidad de la tarea en base a lo hablado
* References: Si se ha realizado ya alguna investigación, documentación o pruebas, añadir enlaces a los recursos relevantes.
* Criterios de aceptación: qué condiciones deben cumplirse para que la tarea se considere completada, en alto nivel.

Si la tarea es para crear un servicio nuevo, introducir "desplegar con /deploy" como DoD, usando el parámetro `definitionOfDoneAdd`, del MCP. No incluirlo como AC.

## Qué no incluir

* No incluir un plan de implementación en la descripción (eso será más adelante)

## Qué no hacer

* No busques el siguiente número incremental de la tarea, el MCP lo deducirá.
