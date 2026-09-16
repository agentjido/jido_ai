defmodule Jido.AI.DSL.Entities do
  @moduledoc false
  defmodule Profile do
    @moduledoc false
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
      memory: []
    ]
  end

  defmodule Models do
    @moduledoc false
    defstruct [:router, :fallback, :__spark_metadata__, entries: [], routers: []]
  end

  defmodule Router do
    @moduledoc false
    defstruct [:module, :fallback, :__spark_metadata__]
  end

  defmodule Model do
    @moduledoc false
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
    @moduledoc false
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
    @moduledoc false
    defstruct [
      :__spark_metadata__,
      max_iterations: 8,
      max_model_calls: 12,
      max_tool_calls: 16,
      timeout: 60_000,
      steering: false,
      idle_timeout: 0,
      tool_heartbeat: 0,
      input: [],
      model: [],
      operation: [],
      output: []
    ]
  end

  defmodule Check do
    @moduledoc false
    defstruct [:module, :when, :__spark_metadata__]
  end

  defmodule Tools do
    @moduledoc false
    defstruct [:__spark_metadata__, entries: []]
  end

  defmodule Skills do
    @moduledoc false
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
    @moduledoc false
    defstruct [:module, :__spark_metadata__]
  end

  defmodule SkillPath do
    @moduledoc false
    defstruct [:path, :__spark_metadata__]
  end

  defmodule Tool do
    @moduledoc false
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
    @moduledoc false
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
    @moduledoc false
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
    @moduledoc false
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
    @moduledoc false
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
    @moduledoc false
    defstruct [:skill, :__spark_metadata__]
  end

  defmodule ToolSkillPath do
    @moduledoc false
    defstruct [:path, :__spark_metadata__]
  end

  defmodule Subagent do
    @moduledoc false
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
    @moduledoc false
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
    @moduledoc false
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

  defmodule Memory do
    @moduledoc false
    defstruct [:history, :__spark_metadata__]
  end

  defmodule Observability do
    @moduledoc false
    defstruct [
      :emit_telemetry,
      :emit_signals,
      :emit_llm_deltas,
      :redact_tool_args,
      :stream_content,
      :store_content,
      :stream_reasoning,
      :store_reasoning,
      :diagnostics_content,
      :__spark_metadata__
    ]
  end
end
