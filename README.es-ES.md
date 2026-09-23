

# SwiftIndex

[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Falexey1312%2Fswift-index%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/alexey1312/swift-index)
[![Swift-versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Falexey1312%2Fswift-index%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/alexey1312/swift-index)
[![CI](https://github.com/alexey1312/swift-index/actions/workflows/ci.yml/badge.svg)](https://github.com/alexey1312/swift-index/actions/workflows/ci.yml)
[![Release](https://github.com/alexey1312/swift-index/actions/workflows/release.yml/badge.svg)](https://github.com/alexey1312/swift-index/actions/workflows/release.yml)
[![License](https://img.shields.io/github/license/alexey1312/swift-index.svg)](LICENSE)

Un motor de búsqueda semántica de código para bases de código Swift, disponible tanto como herramienta CLI como servidor MCP para asistentes de IA como Claude Code.

## Características

- **Búsqueda Híbrida**: Combina la búsqueda de texto completo BM25 con búsqueda vectorial semántica utilizando fusión RRF
- **Análisis Prioritario para Swift**: Usa SwiftSyntax para un análisis preciso de Swift con respaldo en tree-sitter para ObjC, C, JSON, YAML y Markdown
- **Indexación de Metadatos Enriquecidos**: Extrae comentarios de documentación, firmas y rutas jerárquicas (breadcrumbs) para mejorar la calidad de la búsqueda
- **Búsqueda en Documentación**: Indexa documentación independiente (secciones Markdown, encabezados de archivos) como fragmentos de información (InfoSnippets)
- **Mejora de Búsqueda con LLM**: Expansión opcional de consultas, síntesis de resultados y sugerencias de seguimiento
- **Embeddings con Enfoque Local**: Generación de embeddings que preserva la privacidad usando MLX (Apple Silicon) o swift-embeddings
- **Indexación Paralela**: Procesamiento concurrente de archivos con concurrencia acotada para una indexación más rápida
- **Detección de Cambios Basada en Contenido**: Hash de contenido SHA-256 para una reindexación incremental precisa
- **Generación de Descripciones con LLM**: Descripciones generadas automáticamente por IA para fragmentos de código (cuando hay un proveedor LLM disponible)
- **Modo de Observación (Watch)**: Actualiza automáticamente el índice cuando los archivos cambian
- **Servidor MCP**: Expone las capacidades de búsqueda a asistentes de IA a través del Model Context Protocol
- **Compartición de Índices Remotos**: Subida/bajada de índices a S3 o GCS con sincronización delta y búsqueda superpuesta

## Requisitos del Sistema

- **macOS 14 (Sonoma)** o posterior
- **Swift 6.1+** (Xcode 16+). Se recomienda Swift 6.2.3.
- **Apple Silicon** (M1/M2/M3/M4) — requerido para embeddings MLX

## Instalación

### Homebrew (Recomendado)

```bash
brew install alexey1312/swift-index/swiftindex
```

### mise (backend GitHub)

```bash
mise use -g github:alexey1312/swift-index@latest
```

Esto instala SwiftIndex desde las liberaciones de GitHub.

### Desde el Código Fuente

```bash
git clone https://github.com/alexey1312/swift-index.git
cd swift-index
./bin/mise run build:release
cp .build/release/swiftindex /usr/local/bin/
cp .build/release/default.metallib .build/release/mlx.metallib /usr/local/bin/
```

### Verificar la Instalación

```bash
swiftindex --version
swiftindex providers  # Verificar proveedores de embeddings disponibles
```

### Instalar para Asistentes de IA

```bash
# Claude Code (configuración local del proyecto .mcp.json)
swiftindex install-claude-code

# Claude Code (global ~/.claude.json)
swiftindex install-claude-code --global

# Gemini CLI (configuración local del proyecto .gemini.json)
swiftindex install-gemini

# Gemini CLI (global ~/.gemini.json)
swiftindex install-gemini --global

# Cursor (configuración local del proyecto .cursor/mcp.json)
swiftindex install-cursor

# Codex (entrada local del proyecto en ~/.codex/config.toml con cwd)
swiftindex install-codex
```

De forma predeterminada, los comandos de instalación crean una configuración local del proyecto.
Para Cursor, la entrada local del proyecto se escribe en `.cursor/mcp.json`.
Para Codex, la entrada local del proyecto se escribe en `~/.codex/config.toml` con `cwd`.
Usa `--global` para instalar en el archivo de configuración global del usuario en su lugar.

## Inicio Rápido

### 1. Inicializar un Proyecto

```bash
cd /ruta/a/tu/proyecto/swift
swiftindex init
```

Esto crea un archivo de configuración `.swiftindex.toml`.

**Para usuarios de Claude Code Pro/Max**: Selecciona "Claude Code OAuth (Pro/Max)" durante el asistente de inicialización para configurar automáticamente la autenticación OAuth segura a través del Llavero (Keychain).

### 2. Indexar la Base de Código

```bash
swiftindex index .
```

### 3. Buscar

```bash
swiftindex search "flujo de autenticación de usuario"
```

### Autenticación OAuth (Claude Code Pro/Max)

Para una autenticación conveniente y segura con Claude Code:

```bash
# Configurar token OAuth (automático o manual)
swiftindex auth login              # Ejecuta 'claude setup-token' automáticamente
swiftindex auth login --manual     # Caída a entrada manual del token

# Verificar estado de autenticación
swiftindex auth status              # Muestra origen del token (Keychain vs variable de entorno)

# Eliminar token OAuth
swiftindex auth logout
```

Los tokens OAuth se almacenan de forma segura en el Llavero de macOS y funcionan junto con variables de entorno (las variables de entorno tienen prioridad para pruebas/CI/CD).

## Comandos CLI

### `swiftindex index <path>`

Indexa una base de código Swift. Admite apagado seguro (Ctrl+C) para liberar recursos de forma segura.

```bash
# Indexar directorio actual
swiftindex index .

# Forzar reindexación de todos los archivos
swiftindex index --force .

# Modo silencioso (solo barra de progreso y resumen)
swiftindex index --quiet .

# Observar cambios y reindexar automáticamente
swiftindex watch .

# Usar configuración personalizada
swiftindex index --config custom.toml .
```

### `swiftindex search <query>`

Busca en la base de código indexada.

```bash
# Búsqueda básica
swiftindex search "authentication"

# Limitar resultados
swiftindex search --limit 5 "user login"

# Formatos de salida (toon es el predeterminado)
swiftindex search "error handling"                 # Predeterminado: TOON (optimizado para tokens)
swiftindex search --format human "error handling"  # Legible para humanos con % de relevancia
swiftindex search --format json "error handling"   # JSON verboso con todos los metadatos

# Bandera JSON legada (en desuso, usa --format json)
swiftindex search --json "error handling"

# Ajustar peso semántico (0.0 = solo BM25, 1.0 = solo semántico)
swiftindex search --semantic-weight 0.7 "networking code"

# Búsqueda mejorada con LLM (requiere configuración [search.enhancement])
swiftindex search --expand-query "async networking"     # Expandir consulta con términos relacionados
swiftindex search --synthesize "authentication flow"   # Generar resumen y seguimientos
```

**Formatos de Salida:**

| Formato | Descripción                         | Caso de Uso                 |
| ------- | ----------------------------------- | --------------------------- |
| `toon`  | Optimizado para tokens (predeterminado) | Asistentes de IA (57% más pequeño) |
| `human` | Legible con porcentajes de relevancia | Uso en terminal/interactivo |
| `json`  | JSON verboso con todos los metadatos | Automatización/scripts      |

**Banderas de Mejora de Búsqueda:**

| Bandera        | Descripción                                                |
| ---------------- | ---------------------------------------------------------- |
| `--expand-query` | Usar LLM para generar términos de búsqueda relacionados y mejorar el recall |
| `--synthesize`   | Generar resumen de IA de los resultados con sugerencias de seguimiento |

Ambas banderas requieren la configuración `[search.enhancement]`. Consulta [Mejora de Búsqueda](#search-enhancement).

### Almacenamiento Remoto (Compartición de Índices en Equipo)

Comparte índices entre un equipo con almacenamiento remoto:

```bash
swiftindex remote config
swiftindex push
swiftindex pull
swiftindex remote status
```

Consulta `docs/remote-storage.md` para detalles de configuración y ejemplos de CI/CD.

### `swiftindex parse-tree <path>`

Visualiza la estructura AST (Árbol Sintáctico Abstracto) de archivos Swift. Útil para comprender la estructura del código, encontrar declaraciones y explorar el árbol sintáctico.

```bash
# Analizar un solo archivo
swiftindex parse-tree Sources/Sample.swift

# Analizar todos los archivos Swift en un directorio
swiftindex parse-tree Sources/

# Usar patrón glob personalizado
swiftindex parse-tree Sources/ --pattern "**/*Tests.swift"

# Limitar profundidad del AST
swiftindex parse-tree Sources/Sample.swift --max-depth 2

# Filtrar por tipos de nodo
swiftindex parse-tree Sources/ --kind-filter "class,struct,method"

# Formatos de salida
swiftindex parse-tree Sources/Sample.swift                  # Predeterminado: TOON
swiftindex parse-tree Sources/Sample.swift --format human   # Árbol legible para humanos
swiftindex parse-tree Sources/Sample.swift --format json    # JSON verboso
```

**Tipos de Nodo:**

| Tipo        | Descripción               |
| ----------- | ------------------------- |
| `class`     | Declaración de clase      |
| `struct`    | Declaración de struct     |
| `enum`      | Declaración de enum       |
| `protocol`  | Declaración de protocolo  |
| `actor`     | Declaración de actor      |
| `extension` | Declaración de extensión  |
| `function`  | Función de nivel superior |
| `method`    | Método dentro de un tipo  |
| `init`      | Inicializador             |
| `deinit`    | Finalizador               |
| `variable`  | Propiedad variable (`var`) |
| `constant`  | Propiedad constante (`let`) |
| `subscript` | Declaración de subscript  |
| `typealias` | Declaración de alias de tipo |
| `macro`     | Declaración de macro      |

### `swiftindex auth <subcommand>`

Gestiona la autenticación OAuth de Claude Code (solo plataformas Apple).

```bash
# Verificar estado de autenticación
swiftindex auth status

# Configurar token OAuth
swiftindex auth login              # Automático: ejecuta 'claude setup-token'
swiftindex auth login --manual     # Manual: pegar token directamente
swiftindex auth login --force      # Sobrescribir token existente

# Eliminar token OAuth
swiftindex auth logout
```

**Beneficios de OAuth:**

- **Almacenamiento Seguro**: Tokens almacenados en el Llavero de macOS (cifrado por el sistema)
- **Automático**: El asistente de inicialización puede configurar OAuth durante la configuración inicial
- **Prioridad**: Las variables de entorno sobrescriben el Llavero para pruebas/CI/CD
- **Plataforma**: Disponible en macOS, iOS, tvOS, watchOS con Security.framework

**Prioridad de Autenticación** (de mayor a menor):

1. `SWIFTINDEX_ANTHROPIC_API_KEY` — Anulación específica del proyecto
2. `CLAUDE_CODE_OAUTH_TOKEN` — Token OAuth desde el entorno (establecido automáticamente por la CLI de Claude Code)
3. `ANTHROPIC_API_KEY` — Clave API estándar
4. **Token OAuth del Llavero** — Gestionado a través de `swiftindex auth`

### `swiftindex init`

Inicializa la configuración para un proyecto con un asistente interactivo.

```bash
swiftindex init
```

En modo interactivo, el asistente te guía a través de:

1. **Modo de configuración**: Elegir configuración interactiva o usar predeterminados
2. **Proveedor de embeddings**: MLX (más rápido), Swift Embeddings (CPU), Ollama, Voyage o OpenAI
3. **Modelo de embedding**: Opciones específicas del proveedor con respaldo "Personalizado..."
4. **Mejora con LLM**: Expansión opcional de consultas y síntesis de resultados

**Banderas:**

- `--provider <nombre>`: Preseleccionar proveedor de embeddings (omite paso del asistente)
- `--model <nombre>`: Preseleccionar modelo de embedding (omite paso del asistente)
- `--force`: Sobrescribir configuración existente sin solicitar confirmación

**Modo no interactivo:**

Cuando stdin no es un TTY (CI/CD, entrada canalizada), el comando usa automáticamente los valores predeterminados sin solicitar:

```bash
# Amigable para CI: usa predeterminados de MLX
echo "" | swiftindex init

# Con proveedor explícito
swiftindex init --provider swift < /dev/null
```

Sobrescrituras de entorno para pruebas:

- `SWIFTINDEX_TTY_OVERRIDE=noninteractive`: Forzar modo no interactivo
- `SWIFTINDEX_METALTOOLCHAIN_OVERRIDE=present|missing`: Sobrescribir detección de Metal

### `swiftindex config lint` / `swiftindex config format`

Valida o formatea `.swiftindex.toml`.

```bash
swiftindex config lint
swiftindex config format
swiftindex fmt  # alias para config format
```

Banderas para format:

- `-a/--all` formatear todos los `.swiftindex.toml` bajo el directorio actual
- `-c/--check` verificar formato sin escribir
- `-s/--stdin` leer desde stdin y escribir salida formateada en stdout

### `swiftindex watch`

Observa un directorio y actualiza el índice de forma incremental.

```bash
# Observar directorio actual
swiftindex watch

# Observar una ruta específica
swiftindex watch /ruta/a/proyecto
```

### `swiftindex install-claude-code`

Instala SwiftIndex como un servidor MCP para Claude Code.

```bash
# Instalación local del proyecto (crea .mcp.json)
swiftindex install-claude-code

# Instalación global (escribe en ~/.claude.json)
swiftindex install-claude-code --global

# Ejecución de prueba para ver lo que se configuraría
swiftindex install-claude-code --dry-run
```

Existen comandos similares para otros asistentes de IA:

- `swiftindex install-cursor` — IDE Cursor (local: `.cursor/mcp.json`, global: `~/.cursor/mcp.json`)
- `swiftindex install-codex` — CLI Codex (local: `~/.codex/config.toml` con `cwd`, global: `~/.codex/config.toml`)

## Archivos de Guía para Asistentes

Si usas asistentes de IA (Claude Code, Cursor, Codex), agrega `AGENTS.md` y
`CLAUDE.md` en tu repositorio para describir reglas y expectativas del proyecto.

Ejemplo `AGENTS.md`:

```md
# Project Guidance

- Build: ./bin/mise run build
- Tests: ./bin/mise run test
- Config: .swiftindex.toml is linted on load
```

Ejemplo `CLAUDE.md`:

```md
# Assistant Notes

- Use swiftindex for search
- Prefer local embedding providers
- Keep changes small and well tested
```

## Configuración

SwiftIndex utiliza archivos de configuración TOML. Crea `.swiftindex.toml` en la raíz de tu proyecto:

```toml
# .swiftindex.toml

[index]
# Directorios a escanear
include = ["Sources", "Tests"]

# Patrones a excluir
exclude = [
    ".build",
    "Pods",
    "Carthage",
    "DerivedData"
]

# Extensiones de archivo a indexar
extensions = ["swift", "m", "mm", "h", "c", "cpp"]

[embedding]
# Proveedor de embeddings: "mlx", "swift" (alias: swift-embeddings), "ollama", "openai", "voyage"
provider = "mlx"

# Modelo a usar (específico del proveedor)
model = "mlx-community/bge-small-en-v1.5-4bit"

# Dimensión del vector
dimension = 384

[search]
# Número predeterminado de resultados
limit = 20

# Peso semántico para búsqueda híbrida (0.0-1.0)
semantic_weight = 0.7

# Constante de fusión RRF
rrf_k = 60

# Formato de salida: toon (optimizado para tokens), human, o json
output_format = "toon"

[storage]
# Ubicación de almacenamiento del índice
directory = ".swiftindex"
```

Las claves API para proveedores en la nube se leen desde variables de entorno:
`VOYAGE_API_KEY` y `OPENAI_API_KEY`.

### Prioridad de Configuración

La configuración se carga desde múltiples fuentes con la siguiente prioridad (de mayor a menor):

1. **Argumentos CLI**: `--config`, `--limit`, etc.
2. **Variables de entorno**: Prefijadas con `SWIFTINDEX_*`
3. **Configuración del proyecto**: `.swiftindex.toml` en la raíz del proyecto
4. **Configuración global**: `~/.config/swiftindex/config.toml`
5. **Configuración predeterminada**: Valores integrados

### Variables de Entorno

| Variable                        | Descripción                      |
| ------------------------------- | -------------------------------- |
| `SWIFTINDEX_EMBEDDING_PROVIDER` | Proveedor de embeddings          |
| `SWIFTINDEX_EMBEDDING_MODEL`    | Nombre del modelo de embedding   |
| `SWIFTINDEX_LIMIT`              | Límite predeterminado de búsqueda |
| `OPENAI_API_KEY`                | Clave API para embeddings OpenAI |
| `GEMINI_API_KEY`                | Clave API para embeddings Gemini |
| `VOYAGE_API_KEY`                | Clave API para embeddings Voyage AI |

## Mejora de Búsqueda

SwiftIndex admite mejoras opcionales de búsqueda potenciadas por LLM para resultados mejorados:

- **Expansión de Consulta**: Expande automáticamente las consultas de búsqueda con sinónimos y términos relacionados
- **Síntesis de Resultados**: Genera resúmenes de IA de los resultados de búsqueda con puntos clave
- **Sugerencias de Seguimiento**: Sugiere consultas relacionadas para explorar más

### Configuración

Agrega la sección `[search.enhancement]` a tu `.swiftindex.toml`:

```toml
[search.enhancement]
enabled = true  # Habilitar funciones LLM

# Nivel de utilidad: operaciones rápidas (expansión de consulta, seguimientos)
[search.enhancement.utility]
provider = "claude-code-cli"  # o: codex-cli, ollama, openai
# model = "claude-haiku-4-5-20251001"  # sobrescritura de modelo opcional
timeout = 30

# Nivel de síntesis: análisis profundo (resumen de resultados)
[search.enhancement.synthesis]
provider = "claude-code-cli"
# model = "claude-sonnet-4-20250514"  # sobrescritura de modelo opcional
timeout = 120
```

### Proveedores Soportados

| Proveedor       | Requisito                  | Ideal Para                  |
| ----------------- | ------------------------ | --------------------------- |
| `claude-code-cli` | CLI `claude` instalada   | Mejor calidad, usuarios de Claude |
| `codex-cli`       | CLI `codex` instalada    | Usuarios de OpenAI Codex    |
| `ollama`          | Servidor Ollama en ejecución | Local, que preserva privacidad |
| `openai`          | Variable de entorno `OPENAI_API_KEY` | Nube, alta disponibilidad    |
| `gemini`          | Variable de entorno `GEMINI_API_KEY` | Nube, ventana de contexto grande |
| `gemini-cli`      | CLI `gemini` instalada   | Usuarios de Google Gemini CLI |

### Uso

```bash
# Expandir consulta con términos relacionados antes de buscar
swiftindex search --expand-query "async networking"

# Obtener síntesis de IA de los resultados
swiftindex search --synthesize "authentication flow"

# Ambos juntos
swiftindex search --expand-query --synthesize "error handling"
```

Las herramientas MCP aceptan las banderas `expand_query` y `synthesize`. Estas requieren
que `[search.enhancement]` esté habilitado en la configuración.

**Lectura Adicional:**

- [Guía de Mejora de Búsqueda](docs/search-enhancement.md) — Configuración detallada de proveedores LLM
- [Guía de Características de Búsqueda](docs/search-features.md) — Expansión de consulta, síntesis y consejos de búsqueda

## Servidor MCP

SwiftIndex implementa el [Model Context Protocol](https://modelcontextprotocol.io/) versión `2025-11-25` para integración con asistentes de IA.

| Propiedad   | Valor                           |
| --------- | ------------------------------- |
| Transporte | stdio (stdin/stdout)            |
| Formato    | JSON-RPC 2.0                    |
| Herramientas     | 5 herramientas para indexación y búsqueda |

### Configuración por Cliente

Diferentes asistentes de IA requieren formatos de configuración ligeramente distintos:

| Cliente      | Archivo de Configuración                                | Campo de Tipo                  | Notas                        |
| ----------- | ------------------------------------------ | --------------------------- | ---------------------------- |
| Claude Code | `.mcp.json` o `~/.claude.json`            | Requerido: `"type": "stdio"` | Usa `--global` para nivel de usuario |
| Gemini CLI  | `.gemini.json` o `~/.gemini.json`         | Requerido: `"type": "stdio"` | Usa `--global` para nivel de usuario |
| Cursor      | `.cursor/mcp.json` o `~/.cursor/mcp.json` | Requerido: `"type": "stdio"` | Formato JSON `mcp.json`       |
| Codex       | `~/.codex/config.toml`                     | No necesario                  | Formato TOML (cwd para local)  |

### Enlaces de instalación MCP para Cursor

Cursor admite enlaces de instalación para servidores MCP. El parámetro `config` es un objeto JSON codificado en base64
que coincide con el formato `mcp.json` (nombre del servidor como clave de nivel superior). Ejemplo:

```
cursor://anysphere.cursor-deeplink/mcp/install?name=swiftindex&config=<BASE64_JSON>
```

### Respuestas de Error

Las herramientas MCP devuelven errores en formato estándar:

```json
{ "content": [{ "type": "text", "text": "Mensaje de error" }], "isError": true }
```

Errores comunes:

- `"No index found for path: /path"` — Ejecuta `index_codebase` primero
- `"Missing required argument: query"` — Parámetro requerido no proporcionado
- `"Path does not exist or is not a directory"` — Ruta inválida

## Herramientas MCP

Cuando se ejecuta como un servidor MCP, SwiftIndex expone las siguientes herramientas:

### `search_code`

Busca código en la base de código indexada.

**Parámetros:**

- `query` (requerido): Cadena de consulta de búsqueda
- `limit` (opcional): Resultados máximos (predeterminado: 20)
- `semantic_weight` (opcional): Peso para búsqueda semántica (0.0-1.0, predeterminado: 0.7)
- `format` (opcional): Formato de salida - `toon`, `json`, o `human` (predeterminado desde configuración)
- `path` (opcional): Ruta a la base de código indexada (predeterminado: directorio actual)
- `extensions` (opcional): Filtro de extensiones separado por comas (ej., `swift,ts`)
- `path_filter` (opcional): Filtro de ruta (sintaxis glob)
- `expand_query` (opcional): Habilitar expansión de consulta LLM (requiere search.enhancement)
- `synthesize` (opcional): Habilitar síntesis LLM + seguimientos (requiere search.enhancement)

**Ejemplo:**

```json
{
  "query": "flujo de autenticación de usuario",
  "limit": 10,
  "semantic_weight": 0.8,
  "format": "toon"
}
```

### `index_codebase`

Dispara la indexación de la base de código.

**Parámetros:**

- `path` (opcional): Ruta a indexar (predeterminado: directorio actual)
- `force` (opcional): Forzar reindexación de todos los archivos (predeterminado: false)

### `search_docs`

Busca en documentación indexada (archivos Markdown, secciones README, etc.).

**Parámetros:**

- `query` (requerido): Consulta de búsqueda en lenguaje natural
- `limit` (opcional): Resultados máximos (predeterminado: 10)
- `path_filter` (opcional): Filtrar por patrón de ruta (sintaxis glob)
- `format` (opcional): Formato de salida - `toon`, `json`, o `human`
- `path` (opcional): Ruta a la base de código indexada (predeterminado: directorio actual)

**Ejemplo:**

```json
{
  "query": "instrucciones de instalación",
  "limit": 5,
  "path_filter": "*.md"
}
```

### `code_research`

Realiza investigación multinivel sobre la base de código indexada.

**Parámetros:**

- `query` (requerido): Consulta de investigación o tema a investigar
- `path` (opcional): Ruta a la base de código indexada (predeterminado: directorio actual)
- `depth` (opcional): Profundidad máxima de referencia (1-5, predeterminado: 2)
- `focus` (opcional): Uno de `architecture`, `dependencies`, `patterns`, `flow`

**Ejemplo:**

```json
{
  "query": "¿Cómo se configura y usa la mejora de búsqueda?",
  "depth": 3,
  "focus": "architecture"
}
```

### `parse_tree`

Visualiza la estructura AST (Árbol Sintáctico Abstracto) de Swift. Analiza archivos Swift y muestra su jerarquía de declaraciones. Admite tanto archivos individuales como directorios con patrones glob.

**Parámetros:**

- `path` (requerido): Ruta a un archivo Swift o directorio a analizar
- `pattern` (opcional): Patrón glob para directorios (predeterminado: `**/*.swift`)
- `max_depth` (opcional): Profundidad máxima del AST a recorrer
- `kind_filter` (opcional): Lista separada por comas de tipos de nodo a incluir (ej., `class,struct,method`)
- `format` (opcional): Formato de salida - `toon`, `json`, o `human`

**Ejemplo:**

```json
{
  "path": "/ruta/a/Sources",
  "pattern": "**/*.swift",
  "max_depth": 3,
  "kind_filter": "class,struct,method",
  "format": "toon"
}
```

**Tipos de Nodo:** `class`, `struct`, `enum`, `protocol`, `actor`, `extension`, `function`, `method`, `init`, `deinit`, `variable`, `constant`, `subscript`, `typealias`, `macro`

**Resultados por Lote:** Al analizar directorios, los archivos que no se pueden leer (permisos, codificación) se rastorean en el arreglo `skippedFiles` con ruta y motivo.

### Formatos de Salida

El servidor MCP admite tres formatos de salida a través del parámetro `format`:

| Formato | Descripción                         | Caso de Uso                       |
| ------- | ----------------------------------- | ------------------------------ |
| `toon`  | Optimizado para tokens (predeterminado para MCP)   | Asistentes de IA (40-60% más pequeño) |
| `json`  | JSON verboso con todos los metadatos      | Automatización/scripts           |
| `human` | Legible con porcentajes de relevancia | Terminal/interactivo           |

**Estructura del Formato TOON** (Token-Optimized Object Notation):

```
search{q,n}:                    # Consulta y cantidad de resultados
  "cadena de consulta",10

results[n]{r,rel,p,l,k,s}:      # Metadatos tabulares
  1,95,"path.swift",[10,25],"function",["nombreSimbolo"]

meta[n]{sig,bc}:                # Firmas y breadcrumbs
  "func ejemplo()",~            # ~ = nulo

docs[n]:                        # Comentarios de documentación (truncados)
  "Descripción del código..."

descs[n]:                       # Descripciones generadas por LLM
  "Valida credenciales de usuario"  # ~ = nulo si no se generó

code[n]:                        # Contenido de código (máx 15 líneas)
  ---
  func ejemplo() { ... }

synthesis{sum,insights,refs}:   # Resumen LLM (opcional)
  "Resumen de resultados"

follow_ups[n]{q,cat}:           # Consultas relacionadas (opcional)
  "consulta relacionada","más profundo"
```

## Proveedores de Embeddings

SwiftIndex admite múltiples proveedores de embeddings:

### MLX (Predeterminado)

Embeddings acelerados por hardware en Apple Silicon. Opción más rápida para uso local.

```toml
[embedding]
provider = "mlx"
model = "mlx-community/bge-small-en-v1.5-4bit"
```

### Swift Embeddings

Implementación pura en Swift, funciona en todas las plataformas. Respaldo cuando MLX no está disponible.

```toml
[embedding]
provider = "swift" # alias: swift-embeddings
model = "all-MiniLM-L6-v2"
```

### Ollama

Embeddings basados en servidor local a través de Ollama.

```toml
[embedding]
provider = "ollama"
model = "nomic-embed-text"
base_url = "http://localhost:11434"
```

### OpenAI

Embeddings en la nube a través de la API de OpenAI.

```toml
[embedding]
provider = "openai"
model = "text-embedding-3-small"
# Establecer variable de entorno OPENAI_API_KEY
```

### Gemini (Google AI)

Embeddings en la nube a través de la API de Gemini.

```toml
[embedding]
provider = "gemini"
model = "text-embedding-004"
# Establecer variable de entorno GEMINI_API_KEY
```

### Voyage AI

Embeddings optimizados para código a través de Voyage AI.

```toml
[embedding]
provider = "voyage"
model = "voyage-code-2"
# Establecer variable de entorno VOYAGE_API_KEY
```

## Arquitectura

SwiftIndex sigue una arquitectura modular:

```
SwiftIndexCore/
├── Configuration/   # Carga y fusión de configuración
├── Embedding/       # Proveedores de embeddings (MLX, OpenAI, Voyage, Ollama)
├── Index/           # IndexManager (orquestra almacenamiento y embedding)
├── LLM/             # Proveedores LLM para mejora de búsqueda
│   ├── ClaudeCodeCLIProvider  # Integración con CLI de Claude Code
│   ├── CodexCLIProvider       # Integración con CLI de Codex
│   ├── OllamaLLMProvider      # API HTTP de Ollama
│   ├── OpenAILLMProvider      # API HTTP de OpenAI
│   ├── QueryExpander          # Expansión de consultas con LLM
│   ├── ResultSynthesizer      # Resumen multinivel de resultados
│   └── FollowUpGenerator      # Sugerencias de consultas de seguimiento
├── Models/          # Modelos de datos centrales
│   ├── CodeChunk              # Constructos de código con metadatos
│   ├── InfoSnippet            # Fragmentos de documentación independientes
│   └── SearchResult           # Contenedor de resultados de búsqueda
├── Parsing/         # Analizadores SwiftSyntax y tree-sitter
├── Protocols/       # Abstracciones centrales
│   ├── EmbeddingProvider      # Generación de embeddings
│   ├── LLMProvider            # Generación de texto LLM
│   ├── ChunkStore             # Persistencia de fragmentos de código
│   ├── InfoSnippetStore       # Persistencia de fragmentos de documentación
│   └── VectorStore            # Operaciones de índice vectorial
├── Search/          # Motor de búsqueda híbrida con fusión RRF
└── Storage/         # Almacén de fragmentos GRDB + almacén vectorial USearch

SwiftIndexMCP/
├── MCPServer.swift       # Servidor MCP (especificación 2025-11-25)
├── MCPProtocol.swift     # Tipos JSON-RPC y primitivas MCP
├── MCPTasks.swift        # API de tareas para operaciones asíncronas
├── CancellationToken.swift  # Cancelación cooperativa
└── Tools/                # Manejadores de herramientas MCP
    ├── SearchCodeTool
    ├── SearchDocsTool
    ├── IndexCodebaseTool
    ├── CodeResearchTool
    └── WatchCodebaseTool

swiftindex/
└── Commands/        # Comandos CLI
```

### Almacenamiento

- **Almacén de Fragmentos**: Base de datos SQLite con FTS5 para búsqueda de texto completo (GRDB)
- **Almacén de Fragmentos de Info**: Índice FTS5 separado para búsqueda de documentación
- **Almacén Vectorial**: Índice HNSW para búsqueda de vecinos más cercanos aproximados (USearch)

### Algoritmo de Búsqueda

1. Generar embedding de consulta
2. (Opcional) Expandir consulta usando LLM para mejor recall
3. Realizar búsqueda de texto completo BM25 (en fragmentos de código y/o fragmentos de info)
4. Realizar búsqueda de similitud semántica
5. Combinar resultados usando Fusión de Rango Recíproco (RRF)
6. (Opcional) Sintetizar resultados usando LLM para resumen
7. Devolver los top-k resultados ordenados por puntuación fusionada

### Metadatos Indexados

Cada fragmento de código incluye metadatos enriquecidos para mejorar la búsqueda:

| Campo                  | Descripción                                         |
| ---------------------- | --------------------------------------------------- |
| `content`              | El código real                                      |
| `docComment`           | Comentario de documentación asociado                |
| `signature`            | Firma de función/tipo (si aplica)                   |
| `breadcrumb`           | Ruta jerárquica (ej., "Módulo > Clase > Método")    |
| `tokenCount`           | Cantidad aproximada de tokens (content.count / 4)   |
| `language`             | Lenguaje de programación                            |
| `contentHash`          | Hash SHA-256 para detección de cambios              |
| `generatedDescription` | Descripción generada por LLM (cuando hay proveedor) |

## Desarrollo

### Compilación

```bash
swift build
```

### Pruebas

```bash
# Ejecutar todas las pruebas
swift test

# Ejecutar suite de pruebas específica
swift test --filter "E2ETests"

# Ejecutar con cobertura
swift test --enable-code-coverage
```

### Estructura del Proyecto

```
swift-index/
├── Sources/
│   ├── SwiftIndexCore/     # Biblioteca central
│   ├── SwiftIndexMCP/      # Servidor MCP
│   └── swiftindex/         # CLI
├── Tests/
│   ├── SwiftIndexCoreTests/
│   └── IntegrationTests/
└── Package.swift
```

## Solución de Problemas

### Biblioteca Metal de MLX faltante

Las compilaciones de liberación esperan `default.metallib` (y `mlx.metallib`) junto al binario
`swiftindex`. `./bin/mise run build:release` genera estos usando
MetalToolchain.

### Errores de compilación con Xcode

Asegúrate de tener Xcode 16.2+ con las herramientas de línea de comandos instaladas:

```bash
xcode-select --install
xcode-select -p  # Debe mostrar la ruta de Xcode
```

### Índice no se actualiza

Intenta forzar una reindexación:

```bash
swiftindex index --force .
```

### Servidor MCP no responde

Verifica que el servidor esté en ejecución:

```bash
swiftindex serve --verbose
```

Confirma la configuración MCP en el archivo de ajustes de tu asistente de IA.

## Desinstalación

### Homebrew

```bash
brew uninstall swiftindex
```

### Manual

```bash
rm /usr/local/bin/swiftindex
rm -rf ~/.swiftindex  # Opcional: eliminar modelos en caché
```

## Comparación con Alternativas

SwiftIndex está diseñado específicamente para desarrolladores Swift en macOS. Aquí hay cómo se compara con otras herramientas de búsqueda de código:

| Característica       | SwiftIndex            | [mgrep](https://github.com/mixedbread-ai/mgrep) | [ChunkHound](https://github.com/chunkhound/chunkhound) |
| ----------------- | --------------------- | ----------------------------------------------- | ------------------------------------------------------ |
| **Privacidad**     | ✅ Primero local (MLX) | ❌ Solo nube                                    | ✅ Primero local                                        |
| **Análisis Swift** | ✅ SwiftSyntax (AST)  | ❌ Genérico                                      | ⚠️ Tree-sitter                                          |
| **Apple Silicon**  | ✅ Optimizado MLX      | ❌                                              | ❌                                                     |
| **Método de Búsqueda** | BM25 + Semántica + RRF | Semántica + reranking                           | Semántica multinivel                                    |
| **Servidor MCP**   | ✅ Nativo              | ✅ Soporte de agente                            | ❌                                                     |
| **Lenguaje**       | Swift (nativo)        | Rust/Nube                                       | Python                                                 |

### ¿Por qué SwiftIndex?

- **Prioritario para Swift**: El análisis nativo SwiftSyntax extrae metadatos enriquecidos (comentarios de documentación, firmas, breadcrumbs) que los analizadores genéricos omiten
- **Nativo de Apple Silicon**: Los embeddings MLX son 2-3x más rápidos que Ollama en M1/M2/M3, sin latencia de red
- **Búsqueda Híbrida Real**: La fusión RRF de BM25 + búsqueda semántica proporciona mejor recall que los enfoques puramente semánticos
- **Eficiente en Tokens**: El formato de salida TOON ahorra 40-60% de tokens para asistentes de IA
- **Privacidad**: Todo el procesamiento ocurre localmente — tu código nunca sale de tu máquina

### ¿Cuándo usar alternativas?

- **mgrep**: Si necesitas búsqueda multimodal (PDFs, imágenes) o integración con búsqueda web
- **ChunkHound**: Si trabajas principalmente con bases de código Python/JS y no necesitas características específicas de Swift
- **[Context7](https://github.com/upstash/context7)**: Para documentación de bibliotecas externas (complementa SwiftIndex, no es un competidor)

## Licencia

Licencia MIT. Consulta [LICENSE](LICENSE) para detalles.
