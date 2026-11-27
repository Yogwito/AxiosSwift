# AxiosSwift

[![CI](https://github.com/Yogwito/AxiosSwift/actions/workflows/ci.yml/badge.svg?branch=develop)](https://github.com/Yogwito/AxiosSwift/actions/workflows/ci.yml)

El radiotelescopio de Axios captó dos voces que nadie supo explicar: **Kethari** y **Ozh**.
Axios sabe leerlas, pero no escribirlas. Este traductor toma las preguntas de los gobiernos
en español y las escribe en las dos lenguas, listas para transmitir.

Está hecho desde cero en Swift, sin librerías de traducción, y funciona sin conexión. Como
lo que se envía no se puede retirar, el traductor sigue tres reglas: ninguna pregunta se
pierde, no sale nada que el sistema no pueda volver a leer y no se inventa ninguna palabra.

## Empezar

El proyecto requiere Swift 5.9 o superior (macOS, Windows o Linux). SQLite ya viene incluido.

```sh
swift build                    # compila
swift test                     # corre las pruebas
swift run axios inicializar    # carga el manual y las señales de la primera semana
```

## Traducir

```sh
swift run axios traducir "¿Cuándo llegan?"
```

La pregunta puede llegar sin tildes, sin signos, en mayúsculas, con números en letras o con
algún error de escritura: el traductor la entiende igual. Con `--traza` se muestra lo que
hizo cada fase:

```
$ swift run axios traducir "¿Cuándo llegarán nuestras cinco naves?" --traza
[normalizacion]   ¿cuando llegaran nuestras 5 naves?
[lexico]          ¿ SIGNO@1 · cuando PALABRA@2 · llegaran PALABRA@9 · nuestras PALABRA@18 · 5 NUM@27 · naves PALABRA@33 · ? SIGNO@38 · FIN@39
[correccion]      sin cambios
[arbol]           parcial(cuando, circunstancial) · S: 5 nave+pl de(nosotros) · V: llegar 3pl futuro · O: —
[kethari]         kom pai anir kumesh vinime ka
[ozh]             venu ʔasur mar ulo gor ʔenka wem
[validacion]      kethari: válida [INT kom] [S pai anir kumesh] [V vinime] [PREG] | ozh: válida [T venu] [V ʔasur] [P mar] [S ulo gor ʔenka] [INT wem]
[retrotraduccion] K: ¿cuándo · 5 nave de nosotros · llegar/venir [futuro]? | O: …

Kethari: kom pai anir kumesh vinime ka   [válida]
Ozh:     venu ʔasur mar ulo gor ʔenka wem   [válida]
Registrada como #1
```

## Otras órdenes

```sh
swift run axios cargar data/senales_semana2.txt        # señales nuevas o correcciones del manual, sin recompilar
swift run axios palabra teka                           # lo que se sabe de una palabra, en las tres lenguas y en el tiempo
swift run axios historial desde 2026-11-01             # lo que se ha traducido desde esa fecha
swift run axios validar kethari "kom ulesh vinime ka"  # revisa si una frase es correcta en esa lengua
```

`swift run axios ayuda` las muestra todas.

Los datos se guardan en `axios.db`, en la carpeta desde donde se ejecuta el programa. La
variable `AXIOS_DB` permite usar otro archivo; para empezar de cero basta con borrarlo y
volver a `inicializar`.

## Cómo funciona

La pregunta pasa por varias fases, una detrás de otra:

1. **Normalizador:** minúsculas, sin tildes (la ñ se queda) y números en letras a cifras.
2. **Analizador léxico:** un autómata escrito a mano la parte en palabras, números y signos.
3. **Corrector:** arregla las palabras mal escritas con la distancia de Levenshtein, sin
   tocar las que ya son correctas.
4. **Morfología y analizador sintáctico:** entienden la pregunta y arman un árbol que no
   depende de ninguna lengua.
5. **Generadores:** escriben ese árbol en Kethari y en Ozh.
6. **Validadores:** vuelven a leer cada traducción; si no la reconocen, no sale.
7. **Retrotraducción:** pasa al español lo que se va a enviar, para comprobar qué dice.

En el código no hay ni una palabra de Kethari ni de Ozh: el léxico, la gramática y las
señales viven en `data/` y se cargan en la base de datos, que además guarda qué significaba
cada palabra en cada fecha. El detalle de cada fase está en [`docs/memoria.md`](docs/memoria.md)
y las decisiones de diseño, en [`docs/bitacora.md`](docs/bitacora.md).
