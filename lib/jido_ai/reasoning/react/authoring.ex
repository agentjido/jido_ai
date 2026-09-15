defmodule Jido.AI.Reasoning.ReAct.Authoring do
  @moduledoc false
  alias Jido.AI.{Authoring, Profile, ToolCatalog}
  alias Jido.AI.Reasoning.ReAct.Config

  def default_limits(config) do
    with {:ok, profile} <- Profile.new(profile(config, [], %{})) do
      limits = Map.take(profile.controls, [:timeout, :max_tool_calls])

      {:ok,
       %{
         limits
         | timeout: max(limits.timeout, Config.stream_timeout(config) * config.max_iterations)
       }}
    end
  end

  # The stream owner supplies native lifetime and total tool-call bounds.
  # Config has no overall request timeout or total tool-call limit.
  # Provider callbacks, credentials and transport options stay in live context.
  def lower(%Config{} = config, limits, base \\ %{}, tool_interceptor \\ nil) do
    with {:ok, limits} <- Profile.fields(limits, [:timeout, :max_tool_calls], "standalone.limits"),
         true <- Map.has_key?(limits, :timeout) and Map.has_key?(limits, :max_tool_calls),
         {:ok, tools} <- ToolCatalog.from_input(config.tools, tool_defaults(config)),
         {:ok, profile} <- Profile.new(Map.put(profile(config, tools, limits), :tool_interceptor, tool_interceptor)),
         {:ok, base} <- Jido.Agent.Authoring.attrs(base),
         base = Map.merge(default_base(), base),
         base = Map.update!(base, :routes, &[{"ai.react.query", Authoring.ai(:assistant)} | &1]),
         {:ok, agent} <- Authoring.lower(base, [profile]) do
      options = Config.llm_opts(%{config | tools: %{}}) |> Keyword.drop([:tools])

      plugins =
        Enum.map(agent.plugins, fn
          {Jido.AI.Runtime.Plugin, opts} ->
            {Jido.AI.Runtime.Plugin, Keyword.merge(opts, iteration_limit_result?: true, standalone_checkpoints?: true)}

          plugin ->
            plugin
        end)

      {:ok, %{agent | plugins: plugins}, %{ai: %{assistant: %{options: options}}}}
    else
      false -> Profile.error("standalone.limits", "Declare timeout and max_tool_calls")
      {:error, _} = error -> error
    end
  end

  defp profile(config, tools, limits) do
    output = config.output
    repairs = if output && output.on_validation_error == :repair, do: output.retries, else: 0

    %{
      id: :assistant,
      instructions: config.system_prompt,
      models: %{answer: %{model: config.model}},
      tools: tools,
      reasoning: %{
        method: :react,
        model: :answer,
        tool_concurrency: config.tool_exec.concurrency,
        request_transformer: config.request_transformer
      },
      controls:
        Map.merge(limits, %{
          max_iterations: config.max_iterations,
          max_model_calls: config.max_iterations + repairs
        }),
      effect_policy: config.effect_policy,
      observability: %{
        emit_signals?: config.observability.emit_signals?,
        emit_telemetry?: config.observability.emit_telemetry?,
        redact_tool_args?: config.observability.redact_tool_args?,
        emit_llm_deltas?: config.trace.capture_deltas?
      },
      requests: %{
        mode: :session,
        streaming: config.streaming,
        steering: true,
        idle_timeout: Config.stream_timeout(config),
        tool_heartbeat: config.tool_heartbeat_ms
      },
      memory: %{history: :messages},
      result: %{
        into: :result,
        schema: if(output, do: output.schema),
        max_repairs: repairs,
        repair_fun: if(output, do: output.repair_fun),
        on_validation_error: if(output, do: output.on_validation_error, else: :repair)
      }
    }
  end

  @doc false
  def tool_defaults(config),
    do: %{
      forward_context: :all,
      timeout: config.tool_exec.timeout_ms,
      max_retries: config.tool_exec.max_retries,
      retry_backoff: config.tool_exec.retry_backoff_ms
    }

  defp default_base,
    do: %{
      name: "jido_ai_standalone_react",
      schema:
        Zoi.object(%{
          result: Zoi.any() |> Zoi.default(nil),
          messages: Jido.AI.Thread.Projection.schema()
        }),
      routes: []
    }
end
