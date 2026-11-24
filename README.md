# AxiosSwift

[![CI](https://github.com/Yogwito/AxiosSwift/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/Yogwito/AxiosSwift/actions/workflows/ci.yml)

Hace unas semanas, el radiotelescopio de Axios captó dos voces que nadie supo explicar:
**Kethari** y **Ozh**. Axios sabe leerlas, pero no escribirlas. Este proyecto es nuestra
respuesta: un traductor que toma las preguntas de los gobiernos en español y las escribe
en las dos lenguas, listas para transmitir.

Todo está hecho desde cero en Swift. No usamos librerías de traducción ni inteligencia
artificial, y el programa funciona sin conexión.

Como "lo que enviemos no se puede retirar", el traductor sigue tres reglas:

- **Ninguna pregunta se pierde.** Todas quedan guardadas, con su traducción o con la
  razón por la que no se pudo traducir.
- **No sale nada que el sistema no pueda volver a leer.** Antes de aprobar una traducción,
  la revisamos con un analizador propio de cada lengua.
- **No inventamos nada.** Cada palabra viene del manual o de una señal. Si a una lengua le
  falta una palabra, esa traducción no sale y el sistema explica por qué.

## Lo que necesitas

- Swift 5.9 o superior, en macOS (13 o más), Windows o Linux. El CI lo prueba en los tres.
- Nada más: SQLite ya viene incluido en `Sources/CSQLite`.

## Compilar y probar

```sh
swift build       # compila
swift test        # corre todas las pruebas
```

### Si Swift no te funciona: usa Docker

En uno de nuestros computadores, Windows bloqueaba el compilador (Smart App Control no deja
cargar `Workspace.dll` de `swift-build`). Si te pasa algo parecido, o simplemente no tienes Swift
instalado, puedes usar la misma imagen que usa nuestro CI de Linux. Abre Docker Desktop y,
desde la carpeta del proyecto:

```powershell
docker run --rm -v "${PWD}:/app" -v axios-build:/app/.build -w /app swift:6.4.2-noble swift test
```

La primera vez tarda unos minutos porque descarga la imagen y compila todo. Después va
mucho más rápido, porque la compilación queda guardada en el volumen `axios-build` (fuera
del proyecto). Si solo quieres correr un grupo de pruebas, agrega `--filter`, por ejemplo
`swift test --filter PipelineTests`.

## Cómo se usa

Lo primero es cargar el manual y las señales de la primera semana:

```sh
swift run axios inicializar
```

Y ya puedes traducir:

```sh
swift run axios traducir "¿Cuándo llegan?"
swift run axios traducir "¿Cuándo llegan?" --traza   # muestra lo que hizo cada fase
```

No hace falta escribir con cuidado. Las preguntas pueden llegar sin tildes, sin signos, en
mayúsculas, con números en letras o con algún error de dedo: `"CUANDO LLEGARAN NUESTRAS
CINCO NAVES"` da lo mismo que `"¿Cuándo llegarán nuestras cinco naves?"`.

Estas son las demás órdenes:

```sh
swift run axios cargar data/senales_semana2.txt        # señales nuevas o correcciones del manual, sin recompilar
swift run axios palabra teka                           # qué sabemos de una palabra, en las tres lenguas y en el tiempo
swift run axios historial desde 2026-11-01             # lo que se ha traducido desde esa fecha
swift run axios validar kethari "kom ulesh vinime ka"  # revisa si una frase es correcta en esa lengua
swift run axios validar ozh "ʔasur mar shavi wem"
```

Si te pierdes, `swift run axios` (o `swift run axios ayuda`) te muestra todas las órdenes.

### Dónde se guardan los datos

Todo se guarda en `axios.db`, en la carpeta desde donde ejecutes el programa (ese archivo
no se sube a git). Si quieres usar otra base de datos, indícala con la variable `AXIOS_DB`:

```sh
# macOS / Linux
AXIOS_DB=/tmp/prueba.db swift run axios inicializar
```

```powershell
# Windows PowerShell
$env:AXIOS_DB="C:\ruta\prueba.db"
swift run axios inicializar
```

¿Quieres empezar de cero? Borra el archivo de la base de datos y vuelve a `inicializar`.

## Qué pasa por dentro

Una pregunta recorre varias fases, una detrás de otra:

1. **Normalizador.** Pasa todo a minúsculas, quita las tildes (la ñ se queda, porque es
   otra letra), deja solo `¿` y `?` como signos y convierte los números en letras a cifras:
   "dos mil quince" se vuelve 2015.
2. **Analizador léxico.** Un autómata escrito a mano parte la pregunta en palabras, números
   y signos, y recuerda en qué columna estaba cada uno en lo que escribiste.
3. **Corrector.** Si una palabra está mal escrita, busca la más parecida con la distancia de
   Levenshtein. Las palabras que ya son correctas no las toca, y si duda entre dos, prefiere
   no adivinar.
4. **Morfología.** Averigua de qué verbo viene cada forma y en qué persona, número y tiempo
   está, incluido el futuro con "ir a" ("van a llegar").
5. **Analizador sintáctico.** Lee la pregunta siguiendo la gramática del español y arma un
   árbol que la describe sin depender de ninguna lengua.
6. **Generadores.** Escriben ese árbol en Kethari y en Ozh con las reglas del manual.
7. **Validadores.** Vuelven a leer cada traducción con un analizador propio de cada lengua.
   Si no la reconocen, no se aprueba.
8. **Retrotraducción.** Pasa al español lo que se va a enviar, para ver con claridad qué
   dice de verdad.

El **pipeline** se encarga de unirlas, de aplicar las tres reglas y de dejar la traza. Así
se ve una pregunta con `--traza` (las fases del analizador sintáctico están resumidas):

```
$ swift run axios traducir "¿Cuándo llegarán nuestras cinco naves?" --traza
[entrada]         ¿Cuándo llegarán nuestras cinco naves?
[normalizacion]   ¿cuando llegaran nuestras 5 naves?
[lexico]          ¿ SIGNO@1 · cuando PALABRA@2 · llegaran PALABRA@9 · nuestras PALABRA@18 · 5 NUM@27 · naves PALABRA@33 · ? SIGNO@38 · FIN@39
[correccion]      sin cambios
[morfologia]      …
[clasificacion]   …
[sintaxis]        …
[arbol]           …
[kethari]         kom pai anir kumesh vinime ka
[ozh]             venu ʔasur mar ulo gor ʔenka wem
[validacion]      kethari: válida [INT kom] [S pai anir kumesh] [V vinime] [PREG] | ozh: válida …
[retrotraduccion] K: ¿cuándo · 5 nave de nosotros · llegar/venir [futuro]? | O: …

Kethari: kom pai anir kumesh vinime ka   [válida]
Ozh:     venu ʔasur mar ulo gor ʔenka wem   [válida]
Registrada como #1
```

Si quieres el detalle de cada fase (la gramática BNF, la tabla del autómata, el modelo de
datos…), está en [`docs/memoria.md`](docs/memoria.md).

## Los datos

En el código no hay ni una palabra de Kethari ni de Ozh, ni ninguna regla de su gramática:
todo vive en la carpeta `data/` y se carga en la base de datos. Por eso, cuando Axios
manda señales nuevas o corrige el manual, basta con `cargar` el archivo, sin recompilar. Y
como la base de datos guarda la historia de cada palabra, siempre se puede saber qué se
creía que significaba en una fecha.

| Archivo | Qué hay |
|---|---|
| `lexico_v0.7.txt` | Las palabras del manual en español, Kethari y Ozh |
| `reglas_v0.7.txt` | La gramática de cada lengua: orden, sufijos, partículas, base de los números… |
| `vocab_es_v0.7.txt` | Vocabulario español para la morfología y el analizador sintáctico |
| `numeros_es_v0.7.txt` | Los números escritos en letras |
| `senales_semana1.txt`, `senales_semana2.txt` | Las señales decodificadas, y la corrección del manual de la semana 2 |

## Cómo está organizado

```
Sources/
  AxiosCore/      todas las fases, la base de datos y la CLI
  CSQLite/        SQLite incluido en el proyecto
  axios/          el programa que ejecutas
Tests/AxiosTests/ las pruebas automáticas, con pares de pregunta y traducción esperada
data/             léxico, reglas, vocabulario y señales
docs/
  memoria.md        cómo funciona cada fase y por qué la hicimos así
  bitacora.md       cada decisión con su fecha, lo que consideramos y la prueba que la respalda
  contrato-arbol.md el acuerdo entre el analizador sintáctico y los generadores
```

## Reglas que respetamos

El curso pone algunas condiciones, y las cumplimos todas:

- No usamos librerías de traducción ni de procesamiento de lenguaje natural.
- No usamos generadores de analizadores: los autómatas y los analizadores los escribimos a mano.
- No usamos modelos de lenguaje ni servicios en red.
- Las expresiones regulares solo están permitidas en la normalización.
- El léxico y las reglas no están en el código.

## El equipo

| | De qué se encargó |
|---|---|
| P1 | Normalizador, números en letras, analizador léxico, corrector, pipeline y traza, retrotraducción y este README |
| P2 | Morfología verbal, gramática BNF, analizador sintáctico y árbol intermedio |
| P3 | Generadores de Kethari y Ozh, números en las dos lenguas y palabras sin respaldo |
| P4 | Base de datos, carga del manual y las señales, versiones del léxico, validadores, CLI y release |
