# AxiosSwift

Traductor Axios: traduce preguntas a Kethari y Ozh desde la línea de órdenes.

## Requisitos

- Swift 5.9 o superior en macOS (13+), Windows o Linux.
- No hace falta instalar SQLite: va embebido en `Sources/CSQLite` (amalgamation 3.54.1).

## Compilar y probar

```sh
swift build       # compila
swift test        # ejecuta las pruebas
```

## Uso

```sh
swift run axios inicializar                          # carga léxico, reglas y señales de la semana 1
swift run axios traducir "¿Cuándo llegan?" --traza   # traduce y muestra cada fase
swift run axios cargar data/senales_semana2.txt      # carga señales y correcciones sin recompilar
swift run axios palabra teka                         # la palabra en las tres lenguas, sus versiones y señales
swift run axios historial desde 2026-11-01           # lo traducido desde esa fecha
swift run axios validar kethari "kom ulesh vinime ka"  # comprueba la gramática de una frase
swift run axios validar ozh "ʔasur mar shavi wem"
```

`swift run axios` sin argumentos (o `ayuda`) muestra todas las órdenes.

### Base de datos

Por defecto se usa `axios.db` en el directorio actual (está en `.gitignore`). Para usar
otra ruta, define la variable de entorno `AXIOS_DB`:

```sh
# macOS / Linux
AXIOS_DB=/tmp/prueba.db swift run axios inicializar
# o para toda la sesión
export AXIOS_DB=/tmp/prueba.db
```

```powershell
# Windows PowerShell
$env:AXIOS_DB="C:\ruta\prueba.db"
swift run axios inicializar
```

Para empezar de cero basta con borrar el archivo de la base de datos.
