

# OmniAgent

OmniAgent es una gema de motor Rails para construir agentes de IA nativos de la aplicación con herramientas.
Proporciona un DSL ligero para definir agentes, configuraciones de modelo/proveedor, plantillas de prompts,
esquemas de herramientas y callbacks del ciclo de vida de generación.

## Qué Incluye

- `OmniAgent::Agent` runtime con abstracción de proveedor y bucle de invocación de herramientas
- `OmniAgent::Tool` DSL con definiciones de entrada estilo JSON-schema
- Composición de prompts desde archivos ERB en `app/agents/<agent_name>/`
- Callbacks de agente (`before_generation`, `after_generation`)
- Etiquetas de agente y herramienta para estrategias de filtrado
- Integración del proveedor OpenAI lista para usar, más un proveedor Ollama para modelos locales
- Tareas Rake y generadores Rails para andamiaje

## Instalación

Agrega estas líneas al Gemfile de tu aplicación:

```ruby
gem "omni_agent"
```

También agrega el proveedor que estés usando al Gemfile:
```ruby
gem "openai"
```

El proveedor `ollama` también depende de la gema `openai` — se comunica con el endpoint compatible con OpenAI de Ollama, por lo que no se necesita una gema por separado.

Luego ejecuta:

```bash
bundle install
```

## Inicio Rápido

1. Instala los directorios base:

```bash
bundle exec rails generate omni_agent:install
```

2. Genera el andamiaje de un agente:

```bash
bundle exec rails generate omni_agent:agent ResearchAgent --model gpt-4.1-mini --with-tools WeatherLookup Summarize
```

3. Agrega tu clave API en `.env`:

```dotenv
OPENAI_ACCESS_TOKEN=your_api_key_here
```

Para usar Ollama en su lugar, establece `config.default_provider = :ollama` (ver más abajo) y, si es necesario, sobrescribe su endpoint/modelo:

```dotenv
OLLAMA_HOST=http://localhost:11434   # predeterminado
OLLAMA_MODEL=llama3.1                # predeterminado; elige un modelo con capacidad de llamadas a herramientas
OLLAMA_API_KEY=ollama                # no usado por Ollama, pero requerido por el cliente openai
```

4. Implementa el prompt de tu agente y las herramientas opcionales bajo:

```text
app/agents/
	research_agent.rb
	research_agent/
		prompt.md.erb
		tools/
```

## Ejemplo de Agente

```ruby
class ResearchAgent < OmniAgent::Agent
	use_model "gpt-4o-mini"

	before_generation :set_current_user

	def set_current_user
		@user = "Test User"
	end
end
```

## Ejemplo de Herramienta

```ruby
module ResearchAgent::Tools
	class GetWeather < OmniAgent::Tool
		description "Get current weather for a city"
		tags :weather
		metadata category: :utility

		input do
			string :city, description: "City name"
		end

		def execute(city:)
			"Sunny in #{city}"
		end
	end
end
```

## Delegación Multiagente

`delegate_to` convierte a un agente en un supervisor: envuelve otra clase de agente como una herramienta, para que el LLM del supervisor pueda decidir cuándo delegar la tarea. El agente delegado es un agente normal, definido de forma independiente (por ejemplo, `app/agents/research_agent.rb`) — no se necesita un archivo de herramienta manual.

```ruby
class SupervisorAgent < OmniAgent::Agent
	use_model "gpt-4o"

	delegate_to ResearchAgent, as: :research,  description: "Look up factual info"
	delegate_to MathAgent,     as: :calculate, description: "Do arithmetic"
end
```

Cada agente delegado se ejecuta de forma aislada (su propia instancia nueva, sin contexto compartido) y devuelve su respuesta final como resultado de la herramienta. La profundidad de delegación está limitada por `OmniAgent.configuration.max_delegation_depth` (predeterminado `5`) para evitar una delegación recursiva descontrolada; superarla lanza `OmniAgent::MaxDelegationDepthError`.

Pasa `run_alias:` para invocar un método definido mediante `run_aliases` (o cualquier punto de entrada de ejecución sin argumentos) en el agente delegado en lugar de su `#run` predeterminado — útil cuando el subagente debería renderizar un archivo de prompt diferente para llamadas delegadas:

```ruby
class SupervisorAgent < OmniAgent::Agent
	delegate_to SupportAgent, as: :triage_ticket, run_alias: :triage
end
```

Pasa `forward:` para compartir parte (o todo) del contexto del supervisor con el agente delegado — un arreglo de claves de contexto, o `true` para reenviar todo. Las claves omitidas y el valor predeterminado (`forward: []`) mantienen al agente delegado completamente aislado:

```ruby
class SupervisorAgent < OmniAgent::Agent
	delegate_to ResearchAgent, as: :research, forward: [ :user, :locale ]
	delegate_to MathAgent,     as: :calculate, forward: true
end
```

## Streaming

Prefija cualquier punto de entrada de ejecución con `.stream` y pasa un bloque para recibir la respuesta a medida que se genera, en lugar de esperar el resultado completo:

```ruby
ResearchAgent.with(user_id: 42).stream.run("What's new?") do |event|
	case event.type
	when :text        then print event.text
	when :tool_call   then puts "\n[using #{event.tool_name}...]"
	when :tool_result then puts "[#{event.error? ? "failed" : "done"}]"
	when :done        then puts "\n---"
	end
end
```

`.stream` debe ir antes de la llamada (`.stream.run(...)`, no `.run(...).stream`) — sin él, o sin un bloque, el comportamiento no cambia y se devuelve el mismo `Response` de todos modos. Actualmente, solo los proveedores `openai`, `ollama` y `mock` admiten streaming. Consulta [Streaming Responses](omniagent-docs/docs/agent/streaming.mdx) para la referencia completa de eventos.

## Evaluaciones (Evals)

`OmniAgent::Eval` te permite probar la calidad del agente: afirmaciones deterministas (llamadas a herramientas, coincidencia de salida) y puntuación mediante LLM como juez (conectable).

```ruby
class ResearchAgentEval < OmniAgent::Eval
	agent ResearchAgent

	eval_case "answers weather question" do
		input "What's the weather in Paris?"
		expect_tool_call :get_weather, with: { city: "Paris" }
		expect_output to_include: "Paris"
	end

	eval_case "is polite" do
		input "Tell me a joke"
		judge "Is the response friendly and on-topic?", threshold: 0.7
	end

	eval_case "summarizes via the :summarize run alias" do
		run_alias :summarize
		input "Some long article text...", with: { tone: "casual" }
		expect_output to_include: "summary"
	end
end
```

* **`input text, with: {}`**: `with:` se reenvía como `context:` del agente, vinculándose a variables de instancia coincidentes durante la ejecución (por ejemplo, `with: { tone: "casual" }` establece `@tone`).
* **`run_alias`**: Apunta a un método definido mediante `run_aliases` (o cualquier punto de entrada de ejecución sin argumentos) en lugar de `#run` simple — útil cuando ese alias renderiza un archivo de prompt diferente (`<method_name>.md.erb`).

Orden de resolución del proveedor del juez: kwarg `provider:` explícito en `judge` → `OmniAgent.configuration.eval_judge_provider`/`eval_judge_model` → el propio proveedor del agente (predeterminado sin configuración).

### Caché

Las ejecuciones de eval se almacenan en caché de forma predeterminada, con clave en `(agente, run_alias, input, context)`. Volver a ejecutar el mismo caso (por ejemplo, iterando sobre afirmaciones) reproduce la salida en caché en lugar de llamar al proveedor nuevamente, ahorrando tokens. Configúralo o desactívalo:

```ruby
OmniAgent.configure do |config|
	config.eval_cache_enabled = true # predeterminado
	config.eval_cache_path = "tmp/omni_agent_eval_cache.json" # predeterminado
end
```

Omitir la caché para una ejecución (la limpia antes de ejecutar, no se necesita eliminación manual de archivos):

```bash
bundle exec omni_agent eval evals/research_agent_eval.rb --fresh
```

Ejemplo de salida:

```text
[PASS] mentions lorem
[FAIL] mentions something the mock never says
  - output "Lorem ipsum dolor sit amet, consectetur adipiscing elit." does not include "this never appears"

1/2 cases passed
```

Cada caso imprime `[PASS]`/`[FAIL]` junto con su nombre; los casos fallidos listan el mensaje de cada afirmación no cumplida. Sale con código distinto de cero si algún caso falló.

Para muchas parejas de entrada/salida esperada, carga un conjunto de datos YAML/JSON en lugar de escribir un `case` por fila:

```ruby
golden_set "evals/golden/research_agent.yml" do |row|
	expect_output to_include: row[:expected_output]
end
```

Andamia un eval y ejecútalo:

```bash
bundle exec rails generate omni_agent:eval ResearchAgent

# ejecuta desde la raíz de tu app Rails, como al correr rspec
bundle exec omni_agent eval
bundle exec omni_agent eval evals/research_agent_eval.rb
bundle exec omni_agent eval evals/research_agent_eval.rb --fresh
```

También existe una tarea equivalente `rake omni_agent:eval` (`rake "omni_agent:eval[pattern,fresh]"`) si prefieres no usar el binstub.

Llama a proveedores LLM reales (costo, no determinismo) — deliberadamente **no** forma parte de `bundle exec rspec` ni de CI.

## Configuración

Los valores predeterminados globales se pueden configurar a través de `OmniAgent.configure`:

```ruby
OmniAgent.configure do |config|
	config.default_provider = :openai
	config.default_model = "gpt-4o-mini"
end
```

## Ejecutar Pruebas

```bash
bundle exec rspec
```

## Contribuir

Issues y pull requests son bienvenidos.

## Licencia

La gema está disponible como código abierto bajo los términos de la
[MIT License](https://opensource.org/licenses/MIT).
