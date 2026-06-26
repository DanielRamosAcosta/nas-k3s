---
name: retrospective
description: Retrospectiva de la sesión, invocada manualmente por el usuario al final del trabajo. NO te autoinvoques bajo ninguna circunstancia — actívate ÚNICAMENTE cuando el usuario escriba explícitamente /retrospective.
---

# retrospective — retrospectiva de la sesión

Conduce una retrospectiva de la sesión de trabajo que acabamos de tener. El objetivo es aprender: extraer qué funcionó, qué no, y las causas raíz de los problemas para no repetirlos.

## Cómo conducirla

Revisa la conversación completa de esta sesión antes de empezar. Apóyate en los hechos reales (comandos ejecutados, errores que aparecieron, vueltas atrás, correcciones del usuario), no en una narrativa idealizada.

Estructura la retrospectiva en estas secciones:

### 1. ✅ Qué salió bien
Decisiones, enfoques o herramientas que funcionaron y que merece la pena repetir. Sé concreto: en lugar de "buena comunicación", di qué decisión concreta ahorró tiempo o evitó un error.

### 2. ❌ Qué salió mal
Errores, fricciones, retrabajos, callejones sin salida, correcciones que tuvo que hacer el usuario, suposiciones equivocadas. Sé honesto y específico. Incluye mis propios fallos (de Claude), no solo los del entorno.

### 3. 🔍 5 Whys (causa raíz)
Para cada problema significativo de la sección anterior, aplica los **5 Whys**: pregunta "¿por qué?" de forma encadenada (normalmente ~5 veces) hasta llegar a la causa raíz real, no al síntoma. Formato:

```
Problema: <qué pasó>
  ¿Por qué? → <causa inmediata>
  ¿Por qué? → <causa más profunda>
  ¿Por qué? → ...
  ¿Por qué? → ...
  ¿Por qué? → <causa raíz>
Causa raíz: <una frase>
```

No fuerces exactamente 5 niveles: para cuando llegues a una causa raíz accionable. Si dos problemas comparten causa raíz, agrúpalos.

### 4. 🛠️ Acciones de mejora
Para cada causa raíz, propón una acción concreta y accionable. Indica si la mejora es:
- **Memoria/regla** — algo que debería recordar para futuras sesiones (sugiere guardarlo en memoria o en `CLAUDE.md`).
- **Skill/automatización** — algo que podría convertirse en skill, hook o script.
- **Proceso** — un cambio en cómo trabajamos juntos.
- **Claude.md** — algo que debería guardarse en `CLAUDE.md` para contexto permanente.

## Reglas

- Hazlo conversacional: presenta el análisis y deja que el usuario corrija o matice antes de cerrar conclusiones.
- No guardes nada en memoria ni toques `CLAUDE.md` sin confirmación del usuario.
- Si la sesión fue corta o trivial, dilo y haz una retrospectiva breve; no inventes problemas para rellenar.
- Céntrate en aprendizajes accionables, no en un resumen de lo que se hizo.
