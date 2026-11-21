# Memoria

## BNF

## Autómata

## Morfología

La morfología (`Sources/AxiosCore/Morfologia/Morfologia.swift`) recibe una palabra y
dice qué es: de "vendrán" saca *venir, 3.ª persona plural, futuro*; de "naves", *nave en
plural*. No hay ninguna terminación ni ningún verbo escrito en el código: todo está en
`data/vocab_es_v0.7.txt` (tabla `vocab_es`) y en el léxico. El código solo trae el
algoritmo, así que un verbo regular nuevo funciona con solo agregarlo al léxico, y un
irregular se arregla con una fila de datos.

### Datos (`vocab_es`)

| Categoría | Ejemplo | Para qué sirve |
|---|---|---|
| `terminacion_presente` / `_pasado` / `_futuro` | `-aron\|ar\|terminacion_pasado\|p=3;n=pl;t=pasado;base=raiz` | Qué persona, número y tiempo marca una terminación, y a qué clase de verbo (-ar, -er, -ir) se aplica |
| `raiz_irregular` | `vendr-\|venir\|raiz_irregular\|t=futuro` | Raíz que sustituye a la regular en un tiempo |
| `raiz_excluida` | `ven-\|venir\|raiz_excluida\|t=pasado` | Raíz regular que el verbo no usa en ese tiempo |
| `verbo` | `fue\|ser,ir\|verbo\|p=3;n=sg;t=pasado` | Forma supletiva: se toma entera |
| `infinitivo` | `ir\|ir\|infinitivo\|` | Verbo sin traducción propia en el léxico |
| `terminacion_plural` | `-ces\|z\|terminacion_plural\|n=pl` | Plural de los sustantivos (el lema es lo que se repone) |

`base=infinitivo` indica que la terminación va pegada al infinitivo entero (el futuro:
llegar-án); `base=raiz`, que va pegada a la raíz (lleg-an). `clase=er` en una raíz
irregular dice con qué clase se conjuga si no es la de su verbo (estuv-ieron).

### Algoritmo para un verbo

```
analizarVerbo(forma):
    c ← clave(forma)                                  # minúsculas, sin tildes
    si c es una forma supletiva → devolver sus lecturas (un rasgo por cada lema)
    para cada corte, de la terminación más larga a la más corta:
        raíz ← c[..corte]    terminación ← "-" + c[corte..]
        para cada fila de terminación verbal con esa forma:
            irregulares ← lemas de "raíz-" como raiz_irregular en ese tiempo
            regulares   ← si base=infinitivo: [raíz]  si no: [raíz + clase] por clase
                          menos los lemas de "raíz-" como raiz_excluida en ese tiempo
            quedarse con los que son verbos conocidos (léxico o infinitivo de vocab_es)
        si hubo alguna lectura → devolverlas todas (sin repetir)
    devolver []
```

Ejemplos:

| Forma | Corte que funciona | Lectura |
|---|---|---|
| enviaron | envi + -aron (pasado, -ar) | enviar 3pl pasado |
| vendrán | vendr + -an (futuro, raíz irregular) | venir 3pl futuro |
| vienen | vien + -en (presente, raíz irregular, venir es -ir) | venir 3pl presente |
| queremos | quer + -emos (presente, -er) | querer 1pl presente |
| venimos | ven + -imos | venir 1pl presente (el pasado se descarta: `ven-` está excluida) |
| enviamos | envi + -amos | enviar 1pl presente **y** enviar 1pl pasado |
| van | forma supletiva | ir 3pl presente |

Si una forma tiene varias lecturas se devuelven todas, en el orden del archivo de datos:
la morfología no adivina, y el analizador sintáctico elige con el contexto. Para los
sustantivos se hace lo mismo con `terminacion_plural`: "luces" → luc + -es → luz.

### Interfaz

- `analizarVerbo(_:) -> [AnalisisVerbal]`: lecturas como verbo conjugado (rasgos,
  procedencia regular/raíz irregular/supletiva y terminación usada).
- `infinitivo(_:) -> String?`: el infinitivo si la forma lo es ("ir a + infinitivo").
- `analizarSustantivo(_:) -> [AnalisisNominal]`: lema en singular y número.
- `etiquetar(_ tokens:) -> [AnalisisToken]`: todo lo anterior para cada token `.palabra`,
  con su posición; `Morfologia.texto(_:)` es la línea de la traza. "Van a llegar" sale
  como `van: ir 3pl presente | a: — | llegar: inf llegar`: el futuro perifrástico lo
  reconoce el analizador sintáctico, porque abarca tres palabras.
- `reconoce(_:) -> Bool`: para el corrector ortográfico. Las formas regulares ("llegan")
  no están en `vocabularioEspanol()` porque se analizan; el corrector debe preguntar aquí
  antes de corregir una palabra.

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
