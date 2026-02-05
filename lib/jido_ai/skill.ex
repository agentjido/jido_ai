defmodule Jido.AI.Skill do
  @moduledoc """
  Unified skill abstraction for Jido agents.

  Skills can be defined two ways:

  1. **Compile-time modules** using `use Jido.AI.Skill`
  2. **Runtime-loaded SKILL.md files** following the agentskills.io format

  Both present the same API to agents and strategies.

  ## Module-based Skills

      defmodule MyApp.Skills.WeatherAdvisor do
        use Jido.AI.Skill,
          name: "weather-advisor",
          description: "Provides weather-aware travel and activity advice.",
          license: "MIT",
          allowed_tools: ~w(weather_geocode weather_forecast),
          actions: [MyApp.Actions.Weather.Forecast],
          body: \"""
          # Weather Advisor

          ## Workflow
          1. Determine location
          2. Fetch weather data
          3. Provide contextual advice
          \"""
      end

  ## Runtime Skills

  Load SKILL.md files at runtime:

      {:ok, spec} = Jido.AI.Skill.Loader.load("priv/skills/code-review/SKILL.md")
      Jido.AI.Skill.Registry.register(spec)

  ## Unified API

  Both types support the same interface:

      Jido.AI.Skill.manifest(skill)      # Returns the Spec struct
      Jido.AI.Skill.body(skill)          # Returns the skill body text
      Jido.AI.Skill.allowed_tools(skill) # Returns list of allowed tool names
      Jido.AI.Skill.actions(skill)       # Returns list of action modules
  """

  alias Jido.AI.Skill.{Spec, Registry, Error}

  @name_regex ~r/^[a-z0-9]+(-[a-z0-9]+)*$/
  @max_name_length 64
  @max_description_length 1024

  @callback manifest() :: Spec.t()
  @callback body() :: String.t()
  @callback allowed_tools() :: [String.t()]
  @callback actions() :: [module()]
  @callback plugins() :: [module()]

  @doc """
  Returns the manifest (Spec) for a skill.

  Works with both module references and Spec structs.
  """
  @spec manifest(module() | Spec.t() | String.t()) :: Spec.t()
  def manifest(mod) when is_atom(mod), do: mod.manifest()
  def manifest(%Spec{} = spec), do: spec

  def manifest(name) when is_binary(name) do
    case Registry.lookup(name) do
      {:ok, spec} -> spec
      {:error, _} -> raise Error.to_error(%Error.NotFound{name: name})
    end
  end

  @doc """
  Returns the body text for a skill.
  """
  @spec body(module() | Spec.t() | String.t()) :: String.t()
  def body(mod) when is_atom(mod), do: mod.body()

  def body(%Spec{body_ref: {:inline, content}}), do: content
  def body(%Spec{body_ref: {:file, path}}), do: File.read!(path)
  def body(%Spec{body_ref: nil}), do: ""

  def body(name) when is_binary(name) do
    case Registry.lookup(name) do
      {:ok, spec} -> body(spec)
      {:error, _} -> raise Error.to_error(%Error.NotFound{name: name})
    end
  end

  @doc """
  Returns the allowed tools for a skill.
  """
  @spec allowed_tools(module() | Spec.t() | String.t()) :: [String.t()]
  def allowed_tools(mod) when is_atom(mod), do: mod.allowed_tools()
  def allowed_tools(%Spec{allowed_tools: tools}), do: tools

  def allowed_tools(name) when is_binary(name) do
    case Registry.lookup(name) do
      {:ok, spec} -> spec.allowed_tools
      {:error, _} -> raise Error.to_error(%Error.NotFound{name: name})
    end
  end

  @doc """
  Returns the actions for a skill.
  """
  @spec actions(module() | Spec.t() | String.t()) :: [module()]
  def actions(mod) when is_atom(mod), do: mod.actions()
  def actions(%Spec{actions: actions}), do: actions

  def actions(name) when is_binary(name) do
    case Registry.lookup(name) do
      {:ok, spec} -> spec.actions
      {:error, _} -> raise Error.to_error(%Error.NotFound{name: name})
    end
  end

  @doc """
  Returns the plugins for a skill.
  """
  @spec plugins(module() | Spec.t() | String.t()) :: [module()]
  def plugins(mod) when is_atom(mod), do: mod.plugins()
  def plugins(%Spec{plugins: plugins}), do: plugins

  def plugins(name) when is_binary(name) do
    case Registry.lookup(name) do
      {:ok, spec} -> spec.plugins
      {:error, _} -> raise Error.to_error(%Error.NotFound{name: name})
    end
  end

  @doc """
  Resolves a skill reference to a Spec.

  Accepts:
  - Module atoms (compile-time skills)
  - Spec structs (already resolved)
  - String names (runtime registry lookup)
  """
  @spec resolve(module() | Spec.t() | String.t()) :: {:ok, Spec.t()} | {:error, term()}
  def resolve(mod) when is_atom(mod) do
    if function_exported?(mod, :manifest, 0) do
      {:ok, mod.manifest()}
    else
      {:error, %Error.NotFound{name: inspect(mod)}}
    end
  end

  def resolve(%Spec{} = spec), do: {:ok, spec}
  def resolve(name) when is_binary(name), do: Registry.lookup(name)

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Jido.AI.Skill

      name = Keyword.fetch!(opts, :name)
      description = Keyword.fetch!(opts, :description)
      license = Keyword.get(opts, :license)
      compatibility = Keyword.get(opts, :compatibility)
      metadata = Keyword.get(opts, :metadata, %{})

      allowed_tools =
        Jido.AI.Skill.__normalize_allowed_tools__(Keyword.get(opts, :allowed_tools, []))

      actions = Keyword.get(opts, :actions, [])
      plugins = Keyword.get(opts, :plugins, [])
      body = Keyword.get(opts, :body)
      body_file = Keyword.get(opts, :body_file)
      vsn = Keyword.get(opts, :vsn)
      tags = Keyword.get(opts, :tags, [])

      Jido.AI.Skill.__validate_name__!(name)
      Jido.AI.Skill.__validate_description__!(description)

      body_ref = Jido.AI.Skill.__body_ref__(body, body_file)

      @skill_spec %Jido.AI.Skill.Spec{
        name: name,
        description: description,
        license: license,
        compatibility: compatibility,
        metadata: metadata,
        allowed_tools: allowed_tools,
        source: {:module, __MODULE__},
        body_ref: body_ref,
        actions: actions,
        plugins: plugins,
        vsn: vsn,
        tags: tags
      }

      @impl Jido.AI.Skill
      def manifest, do: @skill_spec

      @impl Jido.AI.Skill
      def body, do: Jido.AI.Skill.__get_body__(@skill_spec.body_ref)

      @impl Jido.AI.Skill
      def allowed_tools, do: @skill_spec.allowed_tools

      @impl Jido.AI.Skill
      def actions, do: @skill_spec.actions

      @impl Jido.AI.Skill
      def plugins, do: @skill_spec.plugins
    end
  end

  @doc false
  def __normalize_allowed_tools__(tools) when is_list(tools), do: Enum.map(tools, &to_string/1)

  def __normalize_allowed_tools__(tools) when is_binary(tools), do: String.split(tools, ~r/\s+/, trim: true)

  def __normalize_allowed_tools__(_), do: []

  @doc false
  def __validate_name__!(name) do
    if !(is_binary(name) and
           String.length(name) <= @max_name_length and
           Regex.match?(@name_regex, name)) do
      raise ArgumentError,
            "Invalid skill name '#{name}': must be 1-#{@max_name_length} chars, " <>
              "lowercase alphanumeric with hyphens (e.g., 'my-skill-name')"
    end
  end

  @doc false
  def __validate_description__!(description) do
    if !(is_binary(description) and
           String.length(description) >= 1 and
           String.length(description) <= @max_description_length) do
      raise ArgumentError,
            "Invalid skill description: must be 1-#{@max_description_length} characters"
    end
  end

  @doc false
  def __body_ref__(nil, nil), do: nil
  def __body_ref__(body, nil) when is_binary(body), do: {:inline, body}
  def __body_ref__(nil, path) when is_binary(path), do: {:file, path}

  def __body_ref__(_, _) do
    raise ArgumentError, "Cannot specify both :body and :body_file"
  end

  @doc false
  def __get_body__({:inline, content}), do: content
  def __get_body__({:file, path}), do: File.read!(path)
  def __get_body__(nil), do: ""
end
