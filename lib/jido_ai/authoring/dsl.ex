defmodule Jido.AI.DSL.Entities do
  @moduledoc false
  defmodule Profile do
    defstruct [
      :id,
      :instructions,
      :observability,
      :metadata,
      :effect_policy,
      :tool_interceptor,
      :__spark_metadata__,
      tool_context: %{},
      model_entries: [],
      models: [],
      reasoning: [],
      controls: [],
      tools: [],
      skills: [],
      result: [],
      requests: [],
      memory: []
    ]
  end

  defmodule Models do
    defstruct [:router, :fallback, :__spark_metadata__, entries: [], routers: []]
  end

  defmodule Router do
    defstruct [:module, :fallback, :__spark_metadata__]
  end

  defmodule Model do
    defstruct [
      :first,
      :second,
      :role,
      :model,
      :temperature,
      :max_tokens,
      :timeout,
      :__spark_metadata__,
      generation: [],
      provider_options: %{},
      metadata: %{}
    ]
  end

  defmodule Reasoning do
    defstruct [
      :method,
      :model,
      :request_transformer,
      :effect_policy,
      :__spark_metadata__,
      options: %{},
      tool_concurrency: 4
    ]
  end

  defmodule Controls do
    defstruct [
      :__spark_metadata__,
      max_iterations: 8,
      max_model_calls: 12,
      max_tool_calls: 16,
      timeout: 60_000,
      input: [],
      model: [],
      operation: [],
      output: []
    ]
  end

  defmodule Check do
    defstruct [:module, :when, :__spark_metadata__]
  end

  defmodule Tools do
    defstruct [:__spark_metadata__, entries: []]
  end

  defmodule Skills do
    defstruct [
      :paths,
      :trust,
      :resource_policy,
      :resource_provider,
      :max_depth,
      :max_directories,
      :exclude_directories,
      :__spark_metadata__,
      specs: [],
      modules: [],
      entries: []
    ]
  end

  defmodule Skill do
    defstruct [:module, :__spark_metadata__]
  end

  defmodule SkillPath do
    defstruct [:path, :__spark_metadata__]
  end

  defmodule Tool do
    defstruct [
      :target,
      :as,
      :description,
      :max_retries,
      :retry_backoff,
      :idempotency,
      :approval,
      :metadata,
      :__spark_metadata__,
      forward_context: :public,
      timeout: 5_000
    ]
  end

  defmodule AshResource do
    defstruct [
      :resource,
      :description,
      :approval,
      :__spark_metadata__,
      actions: [],
      metadata: %{}
    ]
  end

  defmodule MCPTools do
    defstruct [
      :endpoint,
      :prefix,
      :transport,
      :client_info,
      :protocol_version,
      :timeout,
      :description,
      :approval,
      :__spark_metadata__,
      tools: [],
      discover: false,
      required: false,
      capabilities: %{},
      timeouts: %{},
      metadata: %{}
    ]
  end

  defmodule Browser do
    defstruct [
      :name,
      :description,
      :approval,
      :__spark_metadata__,
      mode: :read_only,
      allow: [],
      metadata: %{}
    ]
  end

  defmodule Catalog do
    defstruct [
      :catalog,
      :description,
      :approval,
      :__spark_metadata__,
      prefix: "catalog_",
      timeout: 1_500,
      max_calls: 12,
      max_parallel_calls: 8,
      require_read_only: true,
      metadata: %{}
    ]
  end

  defmodule ToolSkill do
    defstruct [:skill, :__spark_metadata__]
  end

  defmodule ToolSkillPath do
    defstruct [:path, :__spark_metadata__]
  end

  defmodule Subagent do
    defstruct [
      :agent,
      :as,
      :description,
      :approval,
      :__spark_metadata__,
      timeout: 30_000,
      forward_context: :public,
      result: :structured,
      metadata: %{}
    ]
  end

  defmodule Handoff do
    defstruct [
      :agent,
      :as,
      :description,
      :approval,
      :__spark_metadata__,
      target: :auto,
      forward_context: :public,
      metadata: %{}
    ]
  end

  defmodule Result do
    defstruct [
      :schema,
      :into,
      :repair_fun,
      :repair_action,
      :on_validation_error,
      :__spark_metadata__,
      max_repairs: 0
    ]
  end

  defmodule Requests do
    defstruct [
      :idle_timeout,
      :tool_heartbeat,
      :__spark_metadata__,
      mode: :turn,
      on_busy: :reject,
      max_requests: 100,
      streaming: false,
      steering: false
    ]
  end

  defmodule Memory do
    defstruct [:history, :__spark_metadata__]
  end

  defmodule Observability do
    defstruct [
      :emit_telemetry,
      :emit_signals,
      :emit_llm_deltas,
      :redact_tool_args,
      :__spark_metadata__
    ]
  end
end

defmodule Jido.AI.DSL.Macros do
  @moduledoc false
  alias Jido.Action.Inline

  defmacro ai(id, do: block) do
    register_api!(__CALLER__)

    quote do
      ai_profile(unquote(id), do: unquote(block))
    end
  end

  def ai(id), do: Jido.AI.Authoring.ai(id)

  defmacro instructions(pattern, options) do
    inline_instructions(pattern, options, __CALLER__)
  end

  defmacro instructions(pattern, options, body) do
    inline_instructions(pattern, options ++ body, __CALLER__)
  end

  defp inline_instructions(pattern, options, caller) do
    unless Keyword.keyword?(options), do: error!(caller, "inline instructions require options")

    parsed = Inline.parse_callback!(pattern, options, caller)

    identity =
      quote do
        [host: Jido.AI.DSL, declaration: unquote(caller.line), role: :instructions]
      end

    compiled =
      Inline.compile!(identity, parsed, caller,
        default_name: "ai_instructions",
        remove_imports: [{__MODULE__, [instructions: 2, instructions: 3]}]
      )

    setter = Jido.AI.DSL.Agent.AiProfile.Options

    quote line: caller.line do
      unquote(compiled.declaration_ast)
      require unquote(setter)
      unquote(setter).instructions(unquote(compiled.target_ast))
    end
  end

  defmacro action(name, pattern, options) do
    inline_action(name, pattern, options, __CALLER__)
  end

  defmacro action(name, pattern, options, body) do
    inline_action(name, pattern, options ++ body, __CALLER__)
  end

  defp inline_action(name, pattern, options, caller) do
    unless is_atom(name) and name not in [nil, true, false],
      do: error!(caller, "inline Action name must be an atom")

    unless Keyword.keyword?(options), do: error!(caller, "inline Action requires options")

    {action_options, tool_options} =
      Keyword.split(options, [:do, :name, :description, :schema, :output_schema, :context])

    parsed =
      Inline.parse_callback!(
        pattern,
        Keyword.put_new(action_options, :name, Atom.to_string(name)),
        caller
      )

    identity =
      quote do
        [host: Jido.AI.DSL, declaration: unquote(name), line: unquote(caller.line), role: :action]
      end

    compiled =
      Inline.compile!(identity, parsed, caller,
        default_name: Atom.to_string(name),
        remove_imports: [{__MODULE__, [action: 3, action: 4]}]
      )

    entity = Jido.AI.DSL.Agent.AiProfile.Tools.Action
    tool_options = Keyword.put_new(tool_options, :as, name)

    quote line: caller.line do
      unquote(compiled.declaration_ast)
      require unquote(entity)
      unquote(entity).action(unquote(compiled.target_ast), unquote(tool_options))
    end
  end

  defp register_api!(caller) do
    unless Module.get_attribute(caller.module, :jido_ai_api_registered) do
      Module.put_attribute(caller.module, :jido_ai_api_registered, true)
      Module.put_attribute(caller.module, :before_compile, Jido.AI.DSL.Compiler)
    end
  end

  defp error!(caller, description),
    do: raise(CompileError, file: caller.file, line: caller.line, description: description)
end

defmodule Jido.AI.DSL.Compiler do
  @moduledoc false

  defmacro __before_compile__(_env) do
    quote location: :keep do
      @doc "Returns all canonical AI profiles by ID."
      def ai_profiles, do: Jido.AI.Agent.profiles(__MODULE__)

      @doc "Returns one canonical AI profile."
      def ai_profile(id), do: Jido.AI.Agent.profile(__MODULE__, id)
    end
  end
end

defmodule Jido.AI.DSL do
  @moduledoc "Spark extension for AI profile declarations inside the core `agent do` block."
  alias Jido.AI.DSL.Entities, as: E

  @model %Spark.Dsl.Entity{
    name: :model,
    target: E.Model,
    args: [:first, {:optional, :second}],
    transform: {__MODULE__, :normalize_model_entity, []},
    schema: [
      first: [type: :any, required: true],
      second: [type: :any],
      generation: [type: :keyword_list, default: []],
      temperature: [type: :number],
      max_tokens: [type: :pos_integer],
      timeout: [type: :pos_integer],
      provider_options: [type: :any, default: %{}],
      metadata: [type: :map, default: %{}]
    ]
  }

  @models %Spark.Dsl.Entity{
    name: :models,
    target: E.Models,
    schema: [router: [type: :atom], fallback: [type: :atom]],
    entities: [
      entries: [@model],
      routers: [
        %Spark.Dsl.Entity{
          name: :router,
          target: E.Router,
          args: [:module],
          schema: [module: [type: :atom, required: true], fallback: [type: :atom]]
        }
      ]
    ]
  }
  @reasoning %Spark.Dsl.Entity{
    name: :reasoning,
    target: E.Reasoning,
    args: [:method],
    schema: [
      method: [type: :atom, required: true],
      options: [type: :any, default: %{}],
      model: [type: :any],
      request_transformer: [type: :atom],
      effect_policy: [type: :any],
      tool_concurrency: [type: :pos_integer, default: 4]
    ]
  }
  @controls %Spark.Dsl.Entity{
    name: :controls,
    target: E.Controls,
    schema: [
      max_iterations: [type: {:or, [:pos_integer, {:in, [:method_default]}]}, default: 8],
      max_model_calls: [type: {:or, [:pos_integer, {:in, [:method_default]}]}, default: 12],
      max_tool_calls: [type: {:or, [:pos_integer, {:in, [:method_default]}]}, default: 16],
      timeout: [type: :pos_integer, default: 60_000]
    ],
    entities:
      Enum.map([:input, :model, :operation, :output], fn stage ->
        {stage,
         [
           %Spark.Dsl.Entity{
             name: stage,
             target: E.Check,
             args: [:module],
             schema: [module: [type: :atom, required: true], when: [type: :any]]
           }
         ]}
      end)
  }
  @tool %Spark.Dsl.Entity{
    name: :action,
    target: E.Tool,
    args: [:target],
    schema: [
      target: [type: :any, required: true],
      as: [type: :atom],
      description: [type: :string],
      max_retries: [type: :non_neg_integer],
      retry_backoff: [type: :non_neg_integer],
      forward_context: [type: :any, default: :public],
      idempotency: [type: :atom],
      approval: [type: :any],
      metadata: [type: :map],
      timeout: [type: :pos_integer, default: 5_000]
    ]
  }
  @ash_resource %Spark.Dsl.Entity{
    name: :ash_resource,
    target: E.AshResource,
    args: [:resource],
    schema: [
      resource: [type: :atom, required: true],
      actions: [type: :any, default: []],
      description: [type: :string],
      approval: [type: :any],
      metadata: [type: :map, default: %{}]
    ]
  }
  @mcp_tools %Spark.Dsl.Entity{
    name: :mcp_tools,
    target: E.MCPTools,
    schema: [
      endpoint: [type: :any, required: true],
      prefix: [type: :string, default: ""],
      tools: [type: :any, default: []],
      discover: [type: :boolean, default: false],
      required: [type: :boolean, default: false],
      transport: [type: :any],
      client_info: [type: :map],
      protocol_version: [type: :string],
      capabilities: [type: :map, default: %{}],
      timeouts: [type: :map, default: %{}],
      timeout: [type: :pos_integer],
      description: [type: :string],
      approval: [type: :any],
      metadata: [type: :map, default: %{}]
    ]
  }
  @browser %Spark.Dsl.Entity{
    name: :browser,
    target: E.Browser,
    args: [:name],
    schema: [
      name: [type: :any, required: true],
      mode: [type: :any, default: :read_only],
      allow: [type: :any, default: []],
      description: [type: :string],
      approval: [type: :any],
      metadata: [type: :map, default: %{}]
    ]
  }
  @catalog %Spark.Dsl.Entity{
    name: :catalog,
    target: E.Catalog,
    args: [:catalog],
    schema: [
      catalog: [type: :atom, required: true],
      prefix: [type: :string, default: "catalog_"],
      timeout: [type: :pos_integer, default: 1_500],
      max_calls: [type: :pos_integer, default: 12],
      max_parallel_calls: [type: :pos_integer, default: 8],
      require_read_only: [type: :boolean, default: true],
      description: [type: :string],
      approval: [type: :any],
      metadata: [type: :map, default: %{}]
    ]
  }
  @tool_skill %Spark.Dsl.Entity{
    name: :skill,
    target: E.ToolSkill,
    args: [:skill],
    schema: [skill: [type: :any, required: true]]
  }
  @tool_skill_path %Spark.Dsl.Entity{
    name: :load_path,
    target: E.ToolSkillPath,
    args: [:path],
    schema: [path: [type: :string, required: true]]
  }
  @subagent %Spark.Dsl.Entity{
    name: :subagent,
    target: E.Subagent,
    args: [:agent],
    schema: [
      agent: [type: :atom, required: true],
      as: [type: :atom],
      description: [type: :string],
      timeout: [type: :pos_integer, default: 30_000],
      forward_context: [type: :any, default: :public],
      result: [type: :any, default: :structured],
      approval: [type: :any],
      metadata: [type: :map, default: %{}]
    ]
  }
  @handoff %Spark.Dsl.Entity{
    name: :handoff,
    target: E.Handoff,
    args: [:agent],
    schema: [
      agent: [type: :atom, required: true],
      as: [type: :atom],
      description: [type: :string],
      target: [type: :any, default: :auto],
      forward_context: [type: :any, default: :public],
      approval: [type: :any],
      metadata: [type: :map, default: %{}]
    ]
  }
  @tools %Spark.Dsl.Entity{
    name: :tools,
    target: E.Tools,
    entities: [
      entries: [
        @tool,
        %{@tool | name: :flow},
        @ash_resource,
        @mcp_tools,
        @browser,
        @catalog,
        @tool_skill,
        @tool_skill_path,
        @subagent,
        @handoff
      ]
    ]
  }
  @skills %Spark.Dsl.Entity{
    name: :skills,
    target: E.Skills,
    schema: [
      paths: [type: :any],
      trust: [type: :any],
      specs: [type: :any, default: []],
      resource_policy: [type: :any],
      resource_provider: [type: :any],
      max_depth: [type: :non_neg_integer],
      max_directories: [type: :pos_integer],
      exclude_directories: [type: {:list, :string}]
    ],
    entities: [
      modules: [
        %Spark.Dsl.Entity{
          name: :skill,
          target: E.Skill,
          args: [:module],
          schema: [module: [type: :atom, required: true]]
        }
      ],
      entries: [
        %Spark.Dsl.Entity{
          name: :load_path,
          target: E.SkillPath,
          args: [:path],
          schema: [path: [type: :string, required: true]]
        }
      ]
    ]
  }
  @result %Spark.Dsl.Entity{
    name: :result,
    target: E.Result,
    args: [{:optional, :schema}],
    schema: [
      schema: [type: :any],
      into: [type: :atom, required: true],
      repair_fun: [type: :any],
      repair_action: [type: :atom],
      on_validation_error: [type: :atom],
      max_repairs: [type: :non_neg_integer, default: 0]
    ]
  }
  @requests %Spark.Dsl.Entity{
    name: :requests,
    target: E.Requests,
    schema: [
      mode: [type: :atom, default: :turn],
      on_busy: [type: :atom, default: :reject],
      max_requests: [type: :pos_integer, default: 100],
      streaming: [type: :boolean, default: false],
      steering: [type: :boolean, default: false],
      idle_timeout: [type: :non_neg_integer],
      tool_heartbeat: [type: :non_neg_integer]
    ]
  }
  @memory %Spark.Dsl.Entity{
    name: :memory,
    target: E.Memory,
    schema: [history: [type: :atom, required: true]]
  }

  @observability %Spark.Dsl.Entity{
    name: :observability,
    target: E.Observability,
    schema: [
      emit_telemetry: [type: :boolean],
      emit_signals: [type: :boolean],
      emit_llm_deltas: [type: :boolean],
      redact_tool_args: [type: :boolean]
    ]
  }
  @profile %Spark.Dsl.Entity{
    name: :ai_profile,
    target: E.Profile,
    args: [:id],
    schema: [
      id: [type: :atom, required: true],
      instructions: [type: :any],
      metadata: [type: :map, default: %{}],
      effect_policy: [type: :any],
      tool_interceptor: [type: :atom],
      tool_context: [type: :any, default: %{}]
    ],
    entities: [
      model_entries: [@model],
      models: [@models],
      reasoning: [@reasoning],
      controls: [@controls],
      tools: [@tools],
      skills: [@skills],
      result: [@result],
      requests: [@requests],
      memory: [@memory],
      observability: [@observability]
    ]
  }

  use Spark.Dsl.Extension,
    dsl_patches: [%Spark.Dsl.Patch.AddEntity{section_path: [:agent], entity: @profile}],
    imports: [Jido.AI.DSL.Macros]

  @behaviour Jido.Agent.Extension

  @impl Jido.Agent.Extension
  def route_target_options, do: [:ai]

  @doc false
  def normalize_model_entity(%E.Model{first: model, second: nil} = entity),
    do: {:ok, %{entity | role: :default, model: model}}

  def normalize_model_entity(%E.Model{first: role, second: model} = entity),
    do: {:ok, %{entity | role: role, model: model}}

  @impl Jido.Agent.Extension
  def lower_agent(config, entities) do
    {profiles, rest} = Enum.split_with(entities, &match?(%E.Profile{}, &1))

    with {:ok, profiles} <- Jido.AI.Profile.traverse(profiles, &profile/1),
         {:ok, config} <- Jido.AI.Authoring.lower_config(config, profiles),
         do: {:ok, config, rest}
  end

  defp profile(entity) do
    with {:ok, models} <- model_entries(entity.models, entity.model_entries),
         {:ok, model_router} <- model_router(models),
         {:ok, reasoning} <- optional(entity.reasoning, :reasoning, nil),
         {:ok, result} <- one(entity.result, :result),
         {:ok, controls} <- optional(entity.controls, :controls, %E.Controls{}),
         {:ok, tools} <- optional(entity.tools, :tools, %E.Tools{}),
         {:ok, skills} <- skill_source(entity.skills),
         {:ok, requests} <- optional(entity.requests, :requests, %E.Requests{}),
         {:ok, memory} <- optional(entity.memory, :memory, %E.Memory{}),
         {:ok, observability} <- optional(entity.observability, :observability, nil),
         roles = Enum.map(models.entries, & &1.role),
         true <- roles == Enum.uniq(roles) do
      controls = plain(controls)

      controls =
        Enum.reduce([:input, :model, :operation, :output], controls, fn stage, acc ->
          Map.update!(acc, stage, fn checks ->
            Enum.map(checks, fn check ->
              if is_nil(check.when),
                do: check.module,
                else: %{module: check.module, when: check.when}
            end)
          end)
        end)

      profile =
        %{
          id: entity.id,
          instructions: entity.instructions,
          observability:
            if(observability,
              do: observability |> plain() |> Map.reject(fn {_, value} -> is_nil(value) end),
              else: %{}
            ),
          metadata: entity.metadata,
          effect_policy: entity.effect_policy || %{},
          tool_interceptor: entity.tool_interceptor,
          tool_context: entity.tool_context,
          skills: skills,
          model_router: model_router,
          models:
            Map.new(models.entries, fn model ->
              {model.role,
               model
               |> plain()
               |> Map.drop([:first, :second, :role])
               |> omit_nil([:temperature, :max_tokens, :timeout])}
            end),
          reasoning:
            if(reasoning,
              do: reasoning |> plain() |> omit_nil([:request_transformer, :effect_policy, :model]),
              else: %{}
            ),
          controls: controls,
          result:
            result
            |> plain()
            |> omit_nil([:schema, :repair_fun, :repair_action, :on_validation_error]),
          requests: requests |> plain() |> omit_nil([:idle_timeout, :tool_heartbeat]),
          memory: plain(memory),
          tools:
            tools.entries
            |> Enum.filter(&match?(%E.Tool{}, &1))
            |> Enum.map(fn tool ->
              name = tool_name(tool)

              tool
              |> plain()
              |> omit_nil([:max_retries, :retry_backoff, :idempotency, :approval, :metadata])
              |> Map.delete(:as)
              |> Map.put(:name, name)
              |> Map.update!(:description, &(&1 || name))
            end),
          tool_sources:
            tools.entries
            |> Enum.reject(&match?(%E.Tool{}, &1))
            |> Enum.map(&tool_source/1)
        }

      profile =
        if models.entries == [],
          do: Map.delete(profile, :models),
          else: profile

      {:ok, profile}
    else
      false -> Jido.AI.Profile.error("models", "Duplicate model role")
      error -> error
    end
  end

  defp model_entries([], entries), do: {:ok, %E.Models{entries: entries}}

  defp model_entries([models], []) do
    {:ok, models}
  end

  defp model_entries(_, _),
    do: Jido.AI.Profile.error("models", "Use one models block or direct model declarations")

  defp model_router(%E.Models{router: nil, routers: []}), do: {:ok, nil}

  defp model_router(%E.Models{router: module, fallback: fallback, routers: []}),
    do: {:ok, %{module: module, fallback: fallback}}

  defp model_router(%E.Models{router: nil, routers: [%E.Router{} = router]}),
    do: {:ok, router |> plain() |> Map.take([:module, :fallback])}

  defp model_router(_),
    do: Jido.AI.Profile.error("models.router", "Declare at most one model router")

  defp tool_name(%{as: name}) when is_atom(name) and name not in [nil, true, false],
    do: Atom.to_string(name)

  defp tool_name(%{target: %Jido.Flow{name: name}}) when is_binary(name), do: name

  defp tool_name(%{target: module}) when is_atom(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :name, 0),
      do: module.name(),
      else: inspect(module)
  end

  defp tool_source(%E.AshResource{} = source), do: source_map(source, :ash_resource, :resource)
  defp tool_source(%E.MCPTools{} = source), do: source_map(source, :mcp_tools, :endpoint)
  defp tool_source(%E.Browser{} = source), do: source_map(source, :browser, :name)
  defp tool_source(%E.Catalog{} = source), do: source_map(source, :catalog, :catalog)
  defp tool_source(%E.ToolSkill{} = source), do: source_map(source, :skill, :skill)
  defp tool_source(%E.ToolSkillPath{} = source), do: source_map(source, :load_path, :path)
  defp tool_source(%E.Subagent{} = source), do: source_map(source, :subagent, :agent)
  defp tool_source(%E.Handoff{} = source), do: source_map(source, :handoff, :agent)

  defp source_map(source, kind, field) do
    source
    |> plain()
    |> Map.put(:kind, kind)
    |> Map.put(:ref, Map.fetch!(source, field))
    |> Map.delete(field)
    |> omit_nil([
      :as,
      :description,
      :approval,
      :transport,
      :client_info,
      :protocol_version,
      :timeout
    ])
  end

  defp plain(value), do: value |> Map.from_struct() |> Map.delete(:__spark_metadata__)

  defp skill_source([]), do: {:ok, nil}

  defp skill_source([entity]) do
    paths = Enum.map(entity.entries, & &1.path)

    if paths != [] and entity.paths != nil do
      Jido.AI.Profile.error("skills.paths", "Use paths or load_path declarations")
    else
      source = entity |> plain() |> Map.delete(:entries)
      source = Map.update!(source, :modules, &Enum.map(&1, fn entry -> entry.module end))
      source = if paths == [], do: source, else: Map.put(source, :paths, paths)

      source =
        if paths != [] and entity.trust == nil, do: Map.put(source, :trust, true), else: source

      Jido.AI.Skill.Source.new(Map.reject(source, fn {_, value} -> value == nil end))
    end
  end

  defp skill_source(_), do: Jido.AI.Profile.error("skills", "Declare at most one skills block")

  defp omit_nil(map, fields),
    do: Map.reject(map, fn {key, value} -> key in fields and is_nil(value) end)

  defp one([value], _), do: {:ok, value}
  defp one(_, name), do: Jido.AI.Profile.error(to_string(name), "Declare exactly one block")
  defp optional([], _, default), do: {:ok, default}
  defp optional(values, name, _), do: one(values, name)
end
