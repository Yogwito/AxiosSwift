# Contrato del árbol intermedio (P2 → P3)

El analizador sintáctico (P2) entrega una `Oracion` por pregunta. Los generadores de
Kethari y Ozh (P3) la reciben y no vuelven a mirar el texto en español. El código está en
`Sources/AxiosCore/Arbol/ArbolIntermedio.swift`.

El árbol es **independiente de la lengua destino**: describe la oración española con lemas,
persona, número, tiempo y polaridad. No trae orden de palabras, afijos ni partículas: eso lo
decide cada generador con las reglas de la BD (`Lexicon.regla`).

## Tipos

```
Oracion       { tipo: TipoOracion, sujeto: Sujeto, verbo: NodoVerbo, objeto: SN? }
TipoOracion   = declarativa | preguntaSiNo | preguntaParcial(Interrogativo)
Sujeto        = explicito(SN) | omitido | interrogativo
SN            { nucleo: Nucleo, cantidad: Int?, poseedor: Pronombre? }      plural (calculado)
Nucleo        = pronombre(Pronombre) | sustantivo(lema: String, plural: Bool)
Pronombre     { lema: String, persona: 1|2|3, plural: Bool }                esPrimeraPlural (calculado)
NodoVerbo     { rasgos: RasgosVerbo, polaridad: afirmativa|negativa, perifrastico: Bool }
RasgosVerbo   { raiz: String, persona: 1|2|3, plural: Bool, tiempo: pasado|presente|futuro }
Interrogativo { lema: String, funcion: sujeto|objeto|circunstancial }
```

## Reglas del contrato

1. **Todos los lemas son claves del léxico** (`BaseDatos.clave`: minúsculas, sin tildes,
   con ñ). Se traducen directamente con `traduccion(es: lema, lengua:, en:)`.
   - Verbo: el infinitivo (`rasgos.raiz`): "vendrán" → `venir`.
   - Sustantivo: el singular: "naves" → `nave`, con `plural: true`.
   - Pronombre: el pronombre personal: "él" → `el`, "ustedes" → `ustedes`.
   - Interrogativo: sin tilde: `cuando`, `que`, `donde`, `cuantos`, `quien`.
2. **Sujeto omitido** (`.omitido`): su persona y número son los de `verbo.rasgos`. Kethari y
   Ozh exigen sujeto (`sujeto_obligatorio = si`), así que el generador repone el pronombre.
3. **Sujeto interrogativo** (`.interrogativo`): el sujeto es la palabra interrogativa
   ("¿Quién envió el mensaje?"). En ese caso `interrogativo.funcion == .sujeto`.
4. **`cuantos`** pregunta por la cantidad de un SN: `funcion` dice cuál (`.sujeto` o
   `.objeto`), y ese SN llega **sin** `cantidad`. Si no hay nombre ("¿Cuántos llegan?"), el
   sujeto es `.interrogativo`.
5. **Cantidad**: un `Int` ya convertido (de 0 a 9 999). El generador lo pasa a la base de
   cada lengua. Si `cantidad > 1`, el nombre también llega con `plural: true`.
6. **Poseedor**: el pronombre del poseedor ("nuestro mundo" → `nosotros`, 1.ª plural). El
   número del SN es el del nombre, no el del poseedor.
7. **Artículos**: no se guardan ("el mensaje" → `mensaje`). Kethari y Ozh no tienen.
8. **Futuro con "ir a"**: "van a llegar" llega como `llegar`, 3.ª plural, `.futuro`, con
   `perifrastico = true`. La marca es solo informativa: `RasgosVerbo` es idéntico al de
   "llegarán" y los generadores no necesitan mirarla.
9. **Negación**: `verbo.polaridad == .negativa` (o `verbo.negado`).
10. **"nosotros"**: el árbol solo marca la 1.ª persona plural (`Pronombre.esPrimeraPlural`,
    o `persona == 1 && plural` en el verbo cuando el sujeto está omitido). **P3 decide**
    la forma incluyente o excluyente (anul/anir) según las reglas que acuerde.
11. **Una sola oración simple** por árbol: un verbo, un sujeto y como mucho un objeto.

## Ejemplos

| Frase | Árbol (`Oracion.texto()`) |
|---|---|
| ¿Cuándo llegan? | `parcial(cuando, circunstancial) · S: omitido · V: llegar 3pl presente · O: —` |
| Queremos paz | `declarativa · S: omitido · V: querer 1pl presente · O: paz` |
| ¿Vienen ustedes? | `pregunta sí/no · S: pron(ustedes) · V: venir 2pl presente · O: —` |
| ¿Quién envió el mensaje? | `parcial(quien, sujeto) · S: interrogativo · V: enviar 3sg pasado · O: mensaje` |
| Quince naves llegaron | `declarativa · S: 15 nave+pl · V: llegar 3pl pasado · O: —` |
| Ellos visitaron nuestro mundo | `declarativa · S: pron(ellos) · V: visitar 3pl pasado · O: mundo de(nosotros)` |
| Nosotros no vimos naves | `declarativa · S: pron(nosotros) · V: ver 1pl pasado negativa · O: nave+pl` |
| Van a llegar | `declarativa · S: omitido · V: llegar 3pl futuro (ir a) · O: —` |

Las pruebas `Tests/AxiosTests/ArbolIntermedioTests.swift` construyen estos árboles.

## Cambios al contrato

Cualquier cambio se avisa en el PR con la sección "Cambio de contrato". Solo se harán
cambios aditivos (campos nuevos con valor por defecto), para no romper los generadores.
