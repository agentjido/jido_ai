# Jido.AI.Skill Implementation Plan

> Integrating the [Agent Skills](https://agentskills.io) open standard into Jido as first-class BEAM citizens.

## Overview

`Jido.AI.Skill` provides a unified skill abstraction that can be backed by:

1. **Compile-time Elixir modules** — `use Jido.AI.Skill` (like `Jido.Action` / `Jido.Plugin`)
2. **Runtime-loaded SKILL.md files** — agentskills.io format parsed at startup

Both present the **same API** to agents and strategies, making skills truly first-class.

---

## 1. Design Principles

### BEAM-Native Approach

| Concern | Solution |
|---------|----------|
| **Compile-time skills** | `use Jido.AI.Skill` macro with Zoi validation |
| **Runtime skills** | Parse SKILL.md → `%Skill.Spec{}` struct |
| **Storage** | ETS registry for manifests, disk for bodies |
| **Progressive disclosure** | Manifest at startup, body loaded on demand |
| **Unified API** | Both types implement same interface functions |

### Pure agentskills.io Spec

Only these frontmatter fields are supported:

| Field | Required | Constraints |
|-------|----------|-------------|
| `name` | Yes | 1-64 chars, `^[a-z0-9]+(-[a-z0-9]+)*$` |
| `description` | Yes | 1-1024 chars |
| `license` | No | String |
| `compatibility` | No | Max 500 chars |
| `metadata` | No | Arbitrary map |
| `allowed-tools` | No | Space-delimited tool names |

**No OpenClaw extensions** (emoji, requires, install specs).

---

## 2. Core Data Structure

### Jido.AI.Skill.Spec

```elixir
defmodule Jido.AI.Skill.Spec do
  @type source :: {:module, module()} | {:file, String.t()}

  @type t :: %__MODULE__{
    # agentskills.io fields
    name: String.t(),
    description: String.t(),
    license: String.t() | nil,
    compatibility: String.t() | nil,
    metadata: map() | nil,
    allowed_tools: [String.t()],
    
    # Jido integration fields
    source: source(),
    body_ref: {:file, String.t()} | {:inline, String.t()} | nil,
    actions: [module()],
    plugins: [module()],
    
    # Optional metadata
    vsn: String.t() | nil,
    tags: [String.t()]
  }

  defstruct [
    :name,
    :description,
    :license,
    :compatibility,
    :metadata,
    allowed_tools: [],
    source: nil,
    body_ref: nil,
    actions: [],
    plugins: [],
    vsn: nil,
    tags: []
  ]
end
```

---

## 3. Unified Skill API

Both module-based and runtime skills implement this interface:

```elixir
defmodule Jido.AI.Skill do
  @callback manifest() :: Spec.t()
  @callback body() :: String.t()
  @callback allowed_tools() :: [String.t()]
  @callback actions() :: [module()]
  @callback plugins() :: [module()]

  # Public API (works with both module and spec)
  def manifest(skill)
  def body(skill)
  def allowed_tools(skill)
  def actions(skill)
  def plugins(skill)
end
```

### Implementation Strategy

```elixir
# For module-based skills
def manifest(mod) when is_atom(mod), do: mod.manifest()
def body(mod) when is_atom(mod), do: mod.body()

# For runtime specs
def manifest(%Spec{} = spec), do: spec
def body(%Spec{body_ref: {:file, path}}), do: load_body_from_file(path)
def body(%Spec{body_ref: {:inline, content}}), do: content
```

---

## 4. Compile-Time Skills: `use Jido.AI.Skill`

### Usage

```elixir
defmodule MyApp.Skills.WeatherAdvisor do
  use Jido.AI.Skill,
    name: "weather-advisor",
    description: "Provides weather-aware travel and activity advice.",
    license: "MIT",
    allowed_tools: ~w(weather_geocode weather_forecast weather_current),
    actions: [
      MyApp.Actions.Weather.Geocode,
      MyApp.Actions.Weather.Forecast
    ],
    body: """
    # Weather Advisor

    ## When to Use
    Activate when users ask about weather, packing, or outdoor activities.

    ## Workflow
    1. Determine location (ask if ambiguous)
    2. Use `weather_geocode` for coordinates
    3. Fetch forecast with `weather_forecast`
    4. Provide contextual advice
    """
end
```

### Alternative: Body from File

```elixir
defmodule MyApp.Skills.CodeReview do
  use Jido.AI.Skill,
    name: "code-review",
    description: "Reviews code for quality, security, and best practices.",
    body_file: "priv/skills/code-review/SKILL.md"
end
```

### Macro Implementation

```elixir
defmodule Jido.AI.Skill do
  defmacro __using__(opts) do
    # Validate at compile time with Zoi
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)
    license = Keyword.get(opts, :license)
    compatibility = Keyword.get(opts, :compatibility)
    metadata = Keyword.get(opts, :metadata, %{})
    allowed_tools = normalize_allowed_tools(Keyword.get(opts, :allowed_tools, []))
    actions = Keyword.get(opts, :actions, [])
    plugins = Keyword.get(opts, :plugins, [])
    body = Keyword.get(opts, :body)
    body_file = Keyword.get(opts, :body_file)
    vsn = Keyword.get(opts, :vsn)
    tags = Keyword.get(opts, :tags, [])

    quote do
      @behaviour Jido.AI.Skill

      @skill_spec %Jido.AI.Skill.Spec{
        name: unquote(name),
        description: unquote(description),
        license: unquote(license),
        compatibility: unquote(compatibility),
        metadata: unquote(Macro.escape(metadata)),
        allowed_tools: unquote(allowed_tools),
        source: {:module, __MODULE__},
        body_ref: unquote(body_ref_ast(body, body_file)),
        actions: unquote(actions),
        plugins: unquote(plugins),
        vsn: unquote(vsn),
        tags: unquote(tags)
      }

      @impl Jido.AI.Skill
      def manifest, do: @skill_spec

      @impl Jido.AI.Skill
      def body do
        case @skill_spec.body_ref do
          {:inline, content} -> content
          {:file, path} -> File.read!(path)
          nil -> ""
        end
      end

      @impl Jido.AI.Skill
      def allowed_tools, do: @skill_spec.allowed_tools

      @impl Jido.AI.Skill
      def actions, do: @skill_spec.actions

      @impl Jido.AI.Skill
      def plugins, do: @skill_spec.plugins
    end
  end
end
```

### Zoi Schema for Validation

```elixir
@skill_opts_schema Zoi.object(%{
  name: Zoi.string()
        |> Zoi.regex(~r/^[a-z0-9]+(-[a-z0-9]+)*$/)
        |> Zoi.max_length(64),
  description: Zoi.string()
               |> Zoi.min_length(1)
               |> Zoi.max_length(1024),
  license: Zoi.string() |> Zoi.optional(),
  compatibility: Zoi.string() |> Zoi.max_length(500) |> Zoi.optional(),
  metadata: Zoi.map() |> Zoi.optional(),
  allowed_tools: Zoi.union([
    Zoi.string(),  # space-delimited
    Zoi.list(Zoi.string())
  ]) |> Zoi.optional() |> Zoi.default([]),
  actions: Zoi.list(Zoi.atom()) |> Zoi.optional() |> Zoi.default([]),
  plugins: Zoi.list(Zoi.atom()) |> Zoi.optional() |> Zoi.default([]),
  body: Zoi.string() |> Zoi.optional(),
  body_file: Zoi.string() |> Zoi.optional(),
  vsn: Zoi.string() |> Zoi.optional(),
  tags: Zoi.list(Zoi.string()) |> Zoi.optional() |> Zoi.default([])
})
```

---

## 5. Runtime Skills: SKILL.md Loading

### Storage Location

```elixir
# config/config.exs
config :jido_ai, :skill_paths, [
  "priv/skills"  # Default
]

# Additional paths can be added at runtime
config :jido_ai, :skill_paths, [
  "priv/skills",
  "/opt/company/skills",
  "~/.jido/skills"
]
```

### Directory Structure

```
priv/skills/
├── weather-advisor/
│   ├── SKILL.md
│   └── references/
│       └── cities.md
├── code-review/
│   └── SKILL.md
└── data-analysis/
    ├── SKILL.md
    └── scripts/
        └── analyze.py
```

### Loader Module

```elixir
defmodule Jido.AI.Skill.Loader do
  @doc "Discover and parse all SKILL.md files from configured paths"
  @spec discover() :: {:ok, [Spec.t()]} | {:error, term()}
  def discover do
    paths = Application.get_env(:jido_ai, :skill_paths, ["priv/skills"])
    
    skills =
      paths
      |> Enum.flat_map(&find_skill_files/1)
      |> Enum.map(&parse_skill_file/1)
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, spec} -> spec end)

    {:ok, skills}
  end

  @doc "Parse a single SKILL.md file"
  @spec parse(String.t()) :: {:ok, Spec.t()} | {:error, term()}
  def parse(path) do
    with {:ok, content} <- File.read(path),
         {:ok, {frontmatter, body}} <- split_frontmatter(content),
         {:ok, attrs} <- decode_yaml(frontmatter),
         {:ok, spec} <- build_spec(attrs, path, body) do
      {:ok, spec}
    end
  end

  defp find_skill_files(root) do
    Path.wildcard(Path.join([root, "**", "SKILL.md"]))
  end

  defp split_frontmatter(content) do
    case Regex.run(~r/\A---\n(.+?)\n---\n(.*)$/s, content) do
      [_, yaml, body] -> {:ok, {yaml, body}}
      nil -> {:error, :no_frontmatter}
    end
  end

  defp build_spec(attrs, path, body) do
    root = Path.dirname(path)
    
    spec = %Spec{
      name: attrs["name"],
      description: attrs["description"],
      license: attrs["license"],
      compatibility: attrs["compatibility"],
      metadata: attrs["metadata"],
      allowed_tools: parse_allowed_tools(attrs["allowed-tools"]),
      source: {:file, path},
      body_ref: {:inline, body},
      actions: [],  # Runtime skills don't have actions
      plugins: []   # Runtime skills don't have plugins
    }

    {:ok, spec}
  end

  defp parse_allowed_tools(nil), do: []
  defp parse_allowed_tools(str) when is_binary(str), do: String.split(str)
  defp parse_allowed_tools(list) when is_list(list), do: list
end
```

---

## 6. ETS Registry

```elixir
defmodule Jido.AI.Skill.Registry do
  use GenServer

  @table :jido_skill_registry

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "List all skill manifests"
  @spec list() :: [Spec.t()]
  def list do
    :ets.tab2list(@table)
    |> Enum.map(fn {_name, spec} -> spec end)
  end

  @doc "Get a skill by name"
  @spec get(String.t()) :: {:ok, Spec.t()} | {:error, :not_found}
  def get(name) do
    case :ets.lookup(@table, name) do
      [{^name, spec}] -> {:ok, spec}
      [] -> {:error, :not_found}
    end
  end

  @doc "Register a skill (module or runtime)"
  @spec register(Spec.t()) :: :ok
  def register(%Spec{name: name} = spec) do
    :ets.insert(@table, {name, spec})
    :ok
  end

  @doc "Reload all skills from configured paths"
  @spec reload() :: :ok
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @doc "Register a module-based skill"
  @spec register_module(module()) :: :ok
  def register_module(mod) when is_atom(mod) do
    register(mod.manifest())
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    load_all_skills()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    :ets.delete_all_objects(@table)
    load_all_skills()
    {:reply, :ok, state}
  end

  defp load_all_skills do
    # Load runtime skills from SKILL.md files
    case Jido.AI.Skill.Loader.discover() do
      {:ok, skills} ->
        Enum.each(skills, &register/1)
      {:error, _} ->
        :ok
    end

    # Module-based skills are registered explicitly or at compile time
    :ok
  end
end
```

---

## 7. ReActAgent Integration

### Extended Options

```elixir
use Jido.AI.ReActAgent,
  name: "weather_agent",
  description: "Weather assistant with travel advice",
  tools: [
    Jido.Tools.Weather,
    Jido.Tools.Weather.Geocode
  ],
  skills: [
    MyApp.Skills.WeatherAdvisor,  # Module skill
    "travel-planner"              # Runtime skill by name
  ],
  system_prompt: "You are a helpful assistant.",
  max_iterations: 10
```

### Skill Resolution

```elixir
defmodule Jido.AI.ReActAgent do
  defp resolve_skills(skill_refs) do
    Enum.map(skill_refs, fn
      mod when is_atom(mod) -> mod.manifest()
      name when is_binary(name) -> 
        case Jido.AI.Skill.Registry.get(name) do
          {:ok, spec} -> spec
          {:error, :not_found} -> raise "Skill not found: #{name}"
        end
    end)
  end
end
```

### Tools Extraction

```elixir
@doc "Extract tool actions from skills"
def tools_from_skills(skills) do
  skills
  |> Enum.flat_map(&Jido.AI.Skill.actions/1)
  |> Enum.uniq()
end
```

### Prompt Injection

```elixir
defp build_system_prompt(base_prompt, skills) do
  skill_sections =
    skills
    |> Enum.map(&format_skill_section/1)
    |> Enum.join("\n\n")

  """
  #{base_prompt}

  ## Available Skills

  #{skill_sections}
  """
end

defp format_skill_section(skill) do
  spec = Jido.AI.Skill.manifest(skill)
  body = Jido.AI.Skill.body(skill)
  
  tools_note = 
    case spec.allowed_tools do
      [] -> ""
      tools -> "\n**Allowed tools:** #{Enum.join(tools, ", ")}"
    end

  """
  ### #{spec.name}
  #{spec.description}#{tools_note}

  #{body}
  """
end
```

### Allowed Tools Enforcement

```elixir
defp validate_skill_tools(skills, agent_tools) do
  agent_tool_names = Enum.map(agent_tools, &tool_name/1) |> MapSet.new()

  Enum.each(skills, fn skill ->
    spec = Jido.AI.Skill.manifest(skill)
    
    case spec.allowed_tools do
      [] -> :ok  # No restriction
      allowed ->
        allowed_set = MapSet.new(allowed)
        available = MapSet.intersection(allowed_set, agent_tool_names)
        
        if MapSet.size(available) == 0 and MapSet.size(allowed_set) > 0 do
          Logger.warning(
            "Skill #{spec.name} specifies allowed_tools #{inspect(allowed)} " <>
            "but none are available in this agent"
          )
        end
    end
  end)
end
```

---

## 8. Module Structure

```
lib/jido_ai/skill/
├── skill.ex              # Main module + `use` macro + behaviour
├── spec.ex               # %Spec{} struct
├── loader.ex             # SKILL.md parsing
├── registry.ex           # ETS-backed registry
├── prompt.ex             # Prompt formatting helpers
└── error.ex              # Splode errors
```

---

## 9. Splode Errors

```elixir
defmodule Jido.AI.Skill.Error do
  use Splode,
    error_classes: [
      parse: Jido.AI.Skill.Error.Parse,
      validation: Jido.AI.Skill.Error.Validation
    ],
    unknown_error: Jido.AI.Skill.Error.Unknown
end

defmodule Jido.AI.Skill.Error.Parse.NoFrontmatter do
  use Splode.Error, fields: [:path], class: :parse
  def message(%{path: path}), do: "No YAML frontmatter in #{path}"
end

defmodule Jido.AI.Skill.Error.Parse.InvalidYaml do
  use Splode.Error, fields: [:path, :reason], class: :parse
  def message(%{path: path, reason: r}), do: "Invalid YAML in #{path}: #{inspect(r)}"
end

defmodule Jido.AI.Skill.Error.Validation.InvalidName do
  use Splode.Error, fields: [:name], class: :validation
  def message(%{name: n}), do: "Invalid skill name: #{n}"
end

defmodule Jido.AI.Skill.Error.NotFound do
  use Splode.Error, fields: [:name], class: :validation
  def message(%{name: n}), do: "Skill not found: #{n}"
end
```

---

## 10. Dependencies

Add to `mix.exs`:

```elixir
defp deps do
  [
    {:yaml_elixir, "~> 2.9"}  # YAML parsing for SKILL.md
  ]
end
```

---

## 11. Implementation Phases

### Phase 1: Core (Day 1)
- [ ] Add `yaml_elixir` dependency
- [ ] `Jido.AI.Skill.Spec` struct
- [ ] `Jido.AI.Skill` behaviour + `__using__` macro
- [ ] Compile-time Zoi validation
- [ ] Unit tests for module-based skills

### Phase 2: Runtime Loading (Day 1)
- [ ] `Jido.AI.Skill.Loader` (SKILL.md parsing)
- [ ] `Jido.AI.Skill.Registry` (ETS GenServer)
- [ ] Application config for skill_paths
- [ ] `Jido.AI.Skill.Error` (Splode)

### Phase 3: ReActAgent Integration (Day 2)
- [ ] `skills:` option in ReActAgent macro
- [ ] Skill resolution (module + name lookup)
- [ ] `tools_from_skills/1` update
- [ ] Prompt injection with skill bodies
- [ ] Allowed tools validation (warning)

### Phase 4: Migration & Examples (Day 2)
- [ ] Example skill in `priv/skills/`
- [ ] Update WeatherAgent to use skills
- [ ] Documentation updates

---

## 12. Example: Complete Weather Skill

### Module-Based (`lib/my_app/skills/weather_advisor.ex`)

```elixir
defmodule MyApp.Skills.WeatherAdvisor do
  use Jido.AI.Skill,
    name: "weather-advisor",
    description: """
    Provides weather-aware travel and activity advice. Use when users ask 
    about weather conditions, packing, outdoor activities, or travel planning.
    """,
    license: "MIT",
    compatibility: "Requires Jido.AI >= 2.0",
    allowed_tools: ~w(weather_geocode weather_forecast weather_current),
    actions: [
      Jido.Tools.Weather,
      Jido.Tools.Weather.Geocode,
      Jido.Tools.Weather.Forecast
    ],
    body: """
    # Weather Advisor

    ## Workflow

    1. **Determine Location**
       - Ask for clarification if location is ambiguous
       - Use `weather_geocode` to convert city names to coordinates

    2. **Fetch Weather Data**
       - `weather_forecast` for multi-day outlook
       - `weather_current` for immediate conditions

    3. **Provide Contextual Advice**
       - Temperature range and trends
       - Precipitation probability
       - Practical clothing recommendations

    ## Common US City Coordinates
    - New York: 40.7128,-74.0060
    - Chicago: 41.8781,-87.6298
    - Seattle: 47.6062,-122.3321

    ## Response Style
    Be conversational. Don't dump data—interpret it.
    """
end
```

### File-Based (`priv/skills/travel-planner/SKILL.md`)

```yaml
---
name: travel-planner
description: Plans multi-destination trips with weather-aware scheduling.
license: MIT
allowed-tools: weather_forecast flight_search hotel_search
metadata:
  author: acme-corp
  version: "1.0"
---

# Travel Planner

## When to Use
Activate when users want to plan trips spanning multiple cities or days.

## Workflow
1. Collect destination list and travel dates
2. Check weather for each destination
3. Suggest optimal visit order based on weather
4. Search for flights and hotels

## Best Practices
- Always confirm dates before searching
- Offer alternatives when weather is poor
```

### Agent Using Both

```elixir
defmodule MyApp.TravelAgent do
  use Jido.AI.ReActAgent,
    name: "travel_agent",
    description: "AI travel assistant",
    tools: [
      Jido.Tools.Weather,
      Jido.Tools.Weather.Geocode,
      Jido.Tools.Weather.Forecast,
      MyApp.Tools.FlightSearch,
      MyApp.Tools.HotelSearch
    ],
    skills: [
      MyApp.Skills.WeatherAdvisor,  # Module skill
      "travel-planner"              # Runtime skill
    ],
    system_prompt: "You are a helpful travel planning assistant."
end
```

---

## 13. Future Enhancements

- **File watcher** — Auto-reload skills on SKILL.md changes (dev mode)
- **Skill search** — Full-text search over skill bodies
- **Skill bundles** — Package skills with assets/references
- **Remote skills** — Fetch skills from URLs/registries
- **Skill versioning** — Track versions, handle upgrades
