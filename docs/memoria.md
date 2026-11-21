# Memoria

## BNF

Gramática del español que reconoce el analizador sintáctico (P2). Se escribió para un
analizador descendente recursivo: cada no terminal es una función con el mismo nombre
(`entrada()`, `clausula()`, `sintInterrog()`, `nucleo()`, `sv()`, `verbo()`, `sn()`,
`determinante()`, `nominal()`). La salida es el árbol intermedio (ver "Árbol intermedio").

### Terminales

La gramática no contiene ninguna palabra del español. Cada terminal es una **categoría**
de token que resuelven los datos (léxico y `vocab_es`) o la morfología:

| Terminal | Un token lo es si… | Ejemplos |
|---|---|---|
| `SIGNO` | es un token `.interrogacion` | ¿ ? |
| `NUM` | es un token `.numero(n)` (el analizador léxico ya convirtió el número) | 15, 9999 |
| `FIN` | es el token `.fin` | |
| `INTERROG` | tiene categoría `interrogativo` en el léxico o en `vocab_es` | qué, cuándo, dónde, cuántas, quién |
| `PRON` | tiene categoría `pronombre` en `vocab_es` | yo, ustedes, ellos |
| `ART` | tiene categoría `articulo` en `vocab_es` | el, una, los |
| `POS` | tiene categoría `posesivo` en `vocab_es` | su, nuestro, mis |
| `NEG` | tiene categoría `negacion` en `vocab_es` | no |
| `PREP` | tiene categoría `preposicion` en `vocab_es` | a |
| `SUST` | `Morfologia.analizarSustantivo` le da alguna lectura | paz, naves |
| `VERBO` | `Morfologia.analizarVerbo` le da alguna lectura | llegan, vendrán, fue |
| `INF` | `Morfologia.infinitivo` lo reconoce | llegar, ir |
| `VERBO_PERIF` | es un `VERBO` cuyo lema y tiempo coinciden con una fila `perifrasis` de `vocab_es` (`ir\|a\|perifrasis\|t=presente`) | van, vamos |

Una palabra puede pertenecer a varios terminales (sin tildes "el" es `ART` y `PRON`); la
regla R12 dice cómo se elige.

### Gramática

```
<entrada>        ::= [SIGNO] <clausula> [SIGNO] FIN
<clausula>       ::= <sint-interrog> <nucleo>
                   | <nucleo>
<sint-interrog>  ::= [PREP] INTERROG [<nominal>]
<nucleo>         ::= [<sn>] <sv> [<sn>] [<sn>]
<sv>             ::= [NEG] <verbo>
<verbo>          ::= VERBO_PERIF PREP INF
                   | VERBO
<sn>             ::= PRON
                   | [<determinante>] [NUM] <nominal>
<determinante>   ::= ART | POS
<nominal>        ::= SUST
```

Cada alternativa se elige mirando el token siguiente (y, solo en R12, uno más): no hay
retroceso.

| No terminal | Qué reconoce | Ejemplos |
|---|---|---|
| `<entrada>` | La frase completa. Los signos son opcionales al principio y al final, así se aceptan preguntas sin signos | "¿Cuándo llegan?", "cuando llegan" |
| `<clausula>` | Una frase con o sin palabra interrogativa al principio | "¿Cuántas naves llegaron?", "Queremos paz" |
| `<sint-interrog>` | La palabra interrogativa, con "a" delante y un nombre detrás opcionales | "a quién", "cuántas naves" |
| `<nucleo>` | Como mucho un sintagma antes del verbo, el verbo y hasta dos después | S V O, V S, V O, V S O |
| `<sv>` | El verbo con negación opcional | "no vimos" |
| `<verbo>` | Un verbo conjugado o el futuro "ir a + infinitivo" | "enviaron", "van a llegar" |
| `<sn>` | Un pronombre, o un nombre con determinante y número opcionales | "ustedes", "su planeta", "quince naves" |
| `<determinante>` | Artículo o posesivo | "los", "nuestro" |
| `<nominal>` | Un sustantivo en singular o plural | "paz", "naves" |

### Reglas que no caben en la BNF

La BNF dice qué secuencias son posibles; estas reglas deciden la concordancia, qué
función tiene cada sintagma y cómo se llena el árbol.

- **R1. Cantidades.** `NUM` debe estar entre 0 y 9 999 (constante `cantidadMaxima` del
  analizador: es el alcance del proyecto, no una regla de la lengua). Si `NUM ≠ 1`, el
  nombre va en plural ("quince naves", "0 naves"); con 1, en singular.
- **R2. Determinante y nombre concuerdan en número**, según el rasgo `n` del artículo o
  del posesivo: "los nave" o "nuestros mundo" son errores.
- **R3. Sujeto antes del verbo.** Un `<sn>` delante del verbo es el sujeto y tiene que
  concordar con él en persona y número. Para comparar se usa el rasgo `pv` del pronombre
  si existe, y si no `p`: "ustedes" (`p=2`, `pv=3`) concuerda con "vienen" (3.ª plural) y
  en el árbol queda como 2.ª persona. Un sustantivo cuenta como 3.ª persona.
- **R4. Sintagmas detrás del verbo.** Si todavía no hay sujeto, el primero que concuerda
  con el verbo es el sujeto ("¿Vienen ustedes?"); el otro es el objeto ("Queremos paz":
  *paz* es 3.ª singular y no concuerda con 1.ª plural). Como mucho hay un objeto.
- **R5. Función del interrogativo**, según el rasgo `f` de `vocab_es`:
  `f=circunstancial` (cuándo, dónde) → circunstancial; `f=objeto` (qué) → objeto;
  `f=sujeto` (quién, cuántos) → sujeto si no hay otro sujeto, no lleva `PREP` delante y
  concuerda con el verbo, y si no, objeto. "¿Quién envió el mensaje?" → sujeto;
  "¿A quién escuchan ustedes?" → objeto; "¿Cuántas naves llegaron?" → sujeto.
- **R6. Lecturas ambiguas de la morfología.** Primero se quedan las lecturas del verbo
  que concuerdan con el sujeto (explícito o interrogativo); si queda más de una, se usa la
  primera en el orden de los datos ("enviamos" → presente). Si ninguna concuerda, es un
  error de concordancia con su columna. Con los posesivos igual: "su" → primer candidato.
- **R7. Sujeto omitido.** Si al final no hay sujeto, el sujeto es `.omitido` y la persona
  y el número salen del verbo ("¿Cuándo llegan?" → 3.ª plural).
- **R8. Tipo de oración.** Con `<sint-interrog>`, pregunta parcial. Si no, pregunta de
  sí/no cuando hay algún `SIGNO` o cuando hay **inversión con pronombre**: el sujeto va
  detrás del verbo y es un `PRON` ("vienen ustedes"). Si no, declarativa: "llegarán quince
  naves" (señal 3, voz Ozh) tiene el sujeto detrás pero es un nombre, y es una afirmación.
- **R9. Futuro con "ir a".** `VERBO_PERIF PREP INF` da el verbo del infinitivo, con la
  persona y el número de "ir", tiempo `.futuro` y `perifrastico = true`. La construcción
  está en los datos (`ir|a|perifrasis|t=presente`: el lema de la fila es la preposición
  que exige), así "ir" y "a" no están escritos en el código. Solo vale con "ir" en el
  tiempo de la fila: "fueron a ver" no es un futuro.
- **R10. Negación.** `NEG` delante del verbo da polaridad negativa, también delante del
  futuro con "ir a" ("no van a llegar").
- **R11. Posesivos.** El poseedor es el pronombre del lema del posesivo ("nuestro" →
  *nosotros*), con la persona y el número de la fila de ese pronombre.
- **R12. Palabras que coinciden sin tildes.** Las claves no tienen tildes, así que "el" y
  "él", "tu" y "tú" son la misma palabra. Si el token siguiente es `NUM` o `SUST`, es
  `ART` o `POS`; si no, es `PRON` ("el mensaje" / "¿Es él…?"). Si una palabra tiene
  lectura verbal y nominal, se prefiere la verbal cuando todavía no hay verbo.

### Ejemplos de análisis

| Entrada | Recorrido | Árbol |
|---|---|---|
| ¿Cuándo llegan? | SIGNO · sint-interrog(cuando) · nucleo(sv) · SIGNO | parcial(cuando, circunstancial) · S: omitido · V: llegar 3pl presente |
| cuando llegan | sint-interrog(cuando) · nucleo(sv) | igual: la palabra interrogativa basta (R8) |
| Queremos paz | nucleo(sv, sn) | declarativa · S: omitido · V: querer 1pl presente · O: paz (R4) |
| vienen ustedes | nucleo(sv, sn=PRON) | pregunta sí/no (R8: inversión con pronombre) |
| llegarán quince naves | nucleo(sv, sn) | declarativa · S: 15 nave+pl (R4, R8) |
| ¿Quién envió el mensaje? | sint-interrog(quien) · nucleo(sv, sn) | parcial(quien, sujeto) · S: interrogativo · O: mensaje (R5) |
| Ellos no van a llegar | nucleo(sn, sv(NEG, VERBO_PERIF PREP INF)) | V: llegar 3pl futuro (ir a) negativa (R9, R10) |
| Ellos visitaron nuestro mundo | nucleo(sn, sv, sn(POS, SUST)) | O: mundo de(nosotros) (R11) |

## Autómata

## Modelo de datos

El esquema está en `Sources/AxiosCore/Recursos/schema.sql` y se puede ejecutar varias
veces sin error (`CREATE ... IF NOT EXISTS`).

```mermaid
erDiagram
    carga ||--o{ lexico : "aporta"
    carga ||--o{ regla : "aporta"
    carga ||--o{ senal : "aporta"
    senal ||--|{ senal_palabra : "se divide en"

    carga {
        INTEGER id PK
        TEXT archivo
        TEXT tipo "lexico | reglas | senales | vocab_es"
        TEXT version_manual
        REAL cargada_en
        INTEGER filas
        TEXT errores
    }
    lexico {
        INTEGER id PK
        TEXT es
        TEXT es_clave
        TEXT lengua "kethari | ozh"
        TEXT forma
        TEXT categoria
        INTEGER carga_id FK
        REAL vigente_desde
        REAL vigente_hasta
    }
    regla {
        INTEGER id PK
        TEXT lengua "kethari | ozh"
        TEXT clave
        TEXT valor
        INTEGER carga_id FK
        REAL vigente_desde
        REAL vigente_hasta
    }
    senal {
        INTEGER id PK
        INTEGER dia
        TEXT voz
        TEXT transcripcion
        TEXT salida
        INTEGER carga_id FK
    }
    senal_palabra {
        INTEGER senal_id PK, FK
        INTEGER posicion PK
        TEXT forma
    }
    vocab_es {
        INTEGER id PK
        TEXT forma
        TEXT lema
        TEXT categoria
        TEXT rasgos
    }
    pregunta {
        INTEGER id PK
        REAL fecha
        TEXT original
        TEXT normalizada
        TEXT correcciones_json
        TEXT kethari
        TEXT ozh
        INTEGER valida_k
        INTEGER valida_o
        TEXT motivo
        TEXT traza
    }
```

**carga.** Registra cada archivo importado: nombre, tipo (`lexico`, `reglas`, `senales`
o `vocab_es`), versión del manual, momento de la carga, filas aceptadas y errores
encontrados. Sirve de auditoría: cada fila de `lexico`, `regla` y `senal` apunta a la
carga que la trajo, así se sabe de qué versión del manual viene un dato.

**lexico.** Diccionario español → Kethari/Ozh. Hay una fila por palabra española y
lengua; `es` guarda la palabra tal como aparece en el manual y `es_clave` la forma
normalizada que se usa para buscar. `forma` es la palabra en la lengua destino y
`categoria` su clase (pronombre, sustantivo, verbo, interrogativo, número). Tiene dos
índices: por español (para traducir) y por forma (para la orden `palabra` y para cruzar
con las señales).

**regla.** Parámetros gramaticales de cada lengua como pares clave/valor: orden de la
oración, sufijos y marcas de tiempo, negación, partículas, base numérica, etc. El
traductor lee estas reglas en vez de tenerlas escritas en el código, por eso cambiar la
gramática no obliga a recompilar.

**senal.** Las señales recibidas: día, voz (kethari, ozh o desconocida), transcripción y
la salida del decodificador. La restricción `UNIQUE (dia, voz, transcripcion)` evita
duplicar una señal si el mismo archivo se carga dos veces.

**senal_palabra.** La transcripción de cada señal partida en palabras con su posición.
Permite preguntar en qué señales aparece una forma y compararla con el léxico. Se borra
en cascada con su señal.

**vocab_es.** Vocabulario español con lema, categoría y rasgos (por ejemplo persona,
número y tiempo de un verbo conjugado). Lo usan el corrector ortográfico y el análisis
morfológico para reconocer palabras de la pregunta.

**pregunta.** Historial de traducciones: la pregunta original, su versión normalizada,
las correcciones ortográficas aplicadas (JSON), el resultado en cada lengua, si cada
traducción pasó la validación, el motivo si no, y la traza de las fases. El índice por
`fecha` sirve a la orden `historial desde <fecha>`.

### Versionado de léxico y reglas

Una corrección del manual **no borra filas**. Cuando llega un significado nuevo, la fila
vigente se cierra poniendo `vigente_hasta = ahora` y se inserta otra con
`vigente_desde = ahora` y `vigente_hasta = NULL`. Así siempre se puede responder "qué
significaba X en la fecha F":

```sql
SELECT forma FROM lexico
WHERE es_clave = :x AND lengua = :lengua
  AND vigente_desde <= :f
  AND (vigente_hasta IS NULL OR vigente_hasta > :f);
```

La traducción actual es la fila con `vigente_hasta IS NULL`. Las fechas se guardan como
`REAL` (segundos Unix con fracción, `Date.timeIntervalSince1970`) para que las
comparaciones sean exactas y no dependan del formato de texto ni de la zona horaria.

## Validadores

Los validadores comprueban si una frase en Kethari u Ozh es gramatical. Están en
`Sources/AxiosCore/Validacion/` y se usan desde la CLI con
`axios validar <kethari|ozh> "<frase>"`. Responden con un `ResultadoValidacion`: si es
válida, la estructura reconocida (por ejemplo `[S ir] [O yorr] [V mi] [PREG]`); si no, el
motivo y la columna donde está el problema.

### Tokenizador (AFD)

`TokenizadorAlien` es un autómata finito determinista escrito a mano, con la tabla de
transiciones explícita en el código (sin expresiones regulares). Separa la frase en
palabras con su columna y solo admite el guion entre dos letras (números como `a-b`).

Clases de caracteres: **letra** (cualquier letra, incluidas `ʔ` y `ü`), **guion** (`-`),
**espacio** y **otro**.

| Estado \ Clase | letra | guion | espacio | otro |
|---|---|---|---|---|
| **inicio** (aceptación) | enPalabra | error | inicio | error |
| **enPalabra** (aceptación) | enPalabra | trasGuion | inicio | error |
| **trasGuion** | enPalabra | error | error | error |
| **error** (sumidero) | — | — | — | — |

- `inicio → enPalabra` abre una palabra y guarda su columna; `enPalabra → inicio` la cierra.
- El estado `trasGuion` existe porque después de un guion solo puede venir una letra:
  así se rechazan `ra-` (guion al final), `-sel` (guion al inicio) y `a--b` (dos guiones).
- Si la entrada termina en `trasGuion` también es error. Al final se agrega un token `fin`.
- Cualquier carácter de la clase **otro** (`#`, cifras, signos) es error con su columna.

### BNF de Kethari

```
<oracion>  ::= [<interrog>] <sn>* <verbo> [<preg>]
<sn>       ::= <pronombre> | [<numero>] [<pronombre>] <nombre>
<nombre>   ::= raiz-sustantivo [sufijo_plural]
<verbo>    ::= [prefijo_negacion] raiz-verbo [sufijo_pasado | sufijo_futuro]
<numero>   ::= <cifra> { separador_numero <cifra> }
<preg>     ::= particula_pregunta
```

Restricciones que se comprueban además de la gramática:

- Sujeto obligatorio: antes del verbo hay al menos un `<sn>` o un `<interrog>`.
- Si hay `<interrog>`, la `<preg>` final es obligatoria.
- Un número mayor que 1 delante de un nombre exige `sufijo_plural` en el nombre.
- Cada cifra debe existir en Kethari y el valor debe ser menor que base^6.
- El verbo va al final; solo puede seguirle la `<preg>`.
- Un pronombre seguido de un nombre es poseedor + nombre cuando ya hay sujeto; si es el
  primer sintagma, el pronombre es el sujeto (`ir yorr mi ka` → `[S ir] [O yorr]`).

Análisis de afijos: primero se busca la palabra completa en el léxico (así los pronombres
plurales, que el manual define como palabras propias, no se confunden con raíz + plural);
si no está, se quitan el prefijo y los sufijos que dicen las reglas y se busca la raíz con
la categoría que corresponde (plural solo en sustantivos, tiempo y negación solo en verbos).

### BNF de Ozh

```
<oracion>   ::= [<tiempo>] [negacion] <verbo> <particula> <sn> {<sn>} [<interrog>]
<tiempo>    ::= marca_pasado | marca_futuro
<verbo>     ::= [prefijo_pregunta] raiz-verbo
<particula> ::= una de la regla "particulas"
<sn>        ::= <pronombre> | [<numero>] <nombre> [<pronombre>]
<numero>    ::= <cifra> { separador_numero <cifra> }
```

Restricciones:

- Una sola marca de tiempo y solo al inicio.
- La partícula va justo después del verbo.
- Sujeto obligatorio: al menos un `<sn>` después de la partícula.
- El `<interrog>` solo puede ir al final y solo si el verbo lleva `prefijo_pregunta`.
- Los nombres no llevan plural: una forma con sufijo no existe en el léxico de Ozh y se
  rechaza como palabra desconocida.
- El poseedor va detrás del nombre (`thüm ʔenka`).

### Implementación

Cada no terminal es una función del analizador descendente recursivo (`oracion`, `sn`,
`nombre`, `verbo`, `numero`, `preg` en Kethari; `oracion`, `tiempo`, `verbo`, `particula`,
`sn`, `nombre`, `numero` en Ozh). Antes de analizar se comprueba que todas las palabras se
puedan clasificar; la primera que no, se informa como `palabra desconocida` con su columna.

Ninguna palabra, afijo ni partícula está escrita en el código: las categorías salen del
léxico (`Lexicon.categoria`), los afijos, marcas, partículas, base y separador de las
reglas (`Lexicon.regla`), y el valor de cada cifra de la traducción de "0", "1", "2"...
Si el manual cambia una regla, basta con cargarla.

### Independencia del generador (rúbrica #13)

Los validadores no importan ni llaman a ninguna función de generación (traducción). Solo
dependen del protocolo `Lexicon` y del tokenizador. Así comprueban lo que produce el
generador de forma independiente: si el generador tuviera un error, el validador no lo
heredaría, y una frase mal generada se rechaza. Un test usa un `LexiconFalso` con palabras
inventadas para demostrar que la gramática no depende de ningún vocabulario concreto.

## Árbol intermedio

El analizador sintáctico no produce texto en otra lengua: produce un árbol (`Oracion`, en
`Sources/AxiosCore/Arbol/ArbolIntermedio.swift`) que describe la pregunta en términos del
español y que leen los dos generadores. Así hay un solo análisis del español y dos
generadores que no se conocen entre sí; agregar una lengua nueva sería escribir solo su
generador.

```mermaid
classDiagram
    Oracion --> TipoOracion
    Oracion --> Sujeto
    Oracion --> NodoVerbo
    Oracion --> SN : objeto?
    TipoOracion --> Interrogativo : preguntaParcial
    Sujeto --> SN : explicito
    SN --> Nucleo
    SN --> Pronombre : poseedor?
    Nucleo --> Pronombre : pronombre
    NodoVerbo --> RasgosVerbo
```

- **Oracion**: tipo (declarativa, pregunta de sí/no o pregunta parcial con su
  interrogativo), sujeto, verbo y objeto opcional.
- **Sujeto**: explícito (un SN), omitido (persona y número salen del verbo) o el propio
  interrogativo ("¿Quién…?").
- **SN**: núcleo (pronombre o sustantivo con su número), cantidad ya convertida a número y
  poseedor opcional. Los artículos no se guardan.
- **NodoVerbo**: `RasgosVerbo` (infinitivo, persona, número, tiempo), polaridad y la marca
  `perifrastico` para el futuro con "ir a".
- **Interrogativo**: su lema y qué pregunta (sujeto, objeto o circunstancia).

La pregunta parcial lleva el interrogativo como valor asociado del tipo, así no se puede
construir una pregunta parcial sin interrogativo ni una declarativa con uno. El contrato
completo, con reglas y ejemplos para los generadores, está en `docs/contrato-arbol.md`.

## Análisis de errores

## Declaración de uso de IA
