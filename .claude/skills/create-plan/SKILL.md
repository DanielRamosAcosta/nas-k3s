---
name: create-plan
description: Explica cómo crear un plan de implementación para una tarea. Usar cuando se ordene crear un plan de implementación.
---

# create-plan — crear un plan de implementación para una tarea

De cara a crear un plan, nos gustan ciclos cortos de feedback, por lo que el plan de implementación debe tener pequeñas fases que permitan obtener feedback rápido y poder iterar sobre la implementación.

Si la tarea conlleva despliegue, podemos intentar desglosar el plan con pequeños despliegues que permitan obtener feedback y comprobar que vamos por el buen camino.

Por ejemplo, si es un servicio que conlleva desplegar un servicio+nueva base de datos+ job de migración, podríamos desglosar así:

* Fase 1: Crear la BBDD
* Fase 2: Crear el job de migración
* Fase 3: Crear el servicio

Con despliegues intermedios, de forma que podamos comprobar que cada fase funciona correctamente antes de pasar a la siguiente.

**Si una fase conlleva despliegue, hazlo EXPLÍCITO en el plan: la fase debe terminar con un paso de "Desplegar" propio y nombrado, seguido de su checkpoint de verificación.** No lo dejes implícito ni lo mezcles dentro de otro paso — debe ser un paso numerado claramente visible (p. ej. "N. **Desplegar** con la skill `/deploy`") para que quien ejecute el plan no se olvide de desplegar al cerrar la fase.

El plan es de ejecución secuencial fase a fase: quien lo ejecute implementa **una** fase, **para**, **despliega esa fase**, **verifica su checkpoint**, y solo entonces empieza la siguiente. No se debe adelantar el código de fases posteriores ni colapsar varias fases en un único despliegue. Por eso el paso de desplegar tiene que estar escrito explícitamente al final de cada fase que lo requiera.

El plan debe leerse como una guía paso a paso de cómo se va a implementar la tarea, con ejemplos de comandos, ficheros a editar, etc.

Cuando tengas el plan, actualiza la tarea con el plan de implementación.

Luego, pásale la tarea a un subagente, y pídele que haga un "dry run" del plan, es decir, que simule la ejecución del plan paso a paso pero sin ejecutar ni tocar ficheros, prediciendo qué saldrá en cada paso. El subagente debe devolver un informe de qué saldría en cada paso, e indicar huecos en el plan, pasos no definidos, contradicciones, desorden de los pasos, etc.

Analiza el informe del subagente y corrige el plan de implementación según sea necesario. Una vez que el plan esté completo y correcto, vuelve a invocar al subagente para que haga un nuevo "dry run" y confirme que el plan es correcto.

Haz esto de forma repetida hasta que el subagente no detecte problemas y el plan sea correcto y completo.
