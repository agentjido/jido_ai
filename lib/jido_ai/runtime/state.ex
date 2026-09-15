defmodule Jido.AI.Runtime.State do
  @moduledoc false

  # One temporary execution map shared by every reasoning method. It is not
  # Agent state or a conversation value. Optional keys stay absent until their
  # phase or method owns them; a nil-filled struct would change dispatch rules.
  @schema Zoi.object(
            %{
              profile: Zoi.struct(Jido.AI.Profile),
              effect_plan: Zoi.object(%{base: Zoi.map(), state: Zoi.map(), directives: Zoi.list(Zoi.any())}),
              request_id: Zoi.string() |> Zoi.min(1),
              run_id: Zoi.string() |> Zoi.min(1),
              started_at_ms: Zoi.integer(),
              model: Zoi.any(),
              options: Zoi.list(Zoi.tuple({Zoi.atom(), Zoi.any()})),
              messages: Zoi.struct(ReqLLM.Context),
              output: Zoi.struct(Jido.AI.Output) |> Zoi.nullable(),
              iterations: Zoi.integer() |> Zoi.min(0),
              model_calls: Zoi.integer() |> Zoi.min(0),
              tool_calls: Zoi.integer() |> Zoi.min(0),
              repairs: Zoi.integer() |> Zoi.min(0),
              usage: Zoi.map(),
              deadline: Zoi.integer(),
              history_delta: Zoi.list(Zoi.map()),
              response: Zoi.struct(ReqLLM.Response) |> Zoi.optional(),
              llm_call_id: Zoi.string() |> Zoi.optional(),
              response_meta: Zoi.map() |> Zoi.optional(),
              tool_meta: Zoi.map() |> Zoi.optional(),
              output_meta: Zoi.map() |> Zoi.optional(),
              output_raw: Zoi.any() |> Zoi.optional(),
              object_request: Zoi.boolean() |> Zoi.optional(),
              repair_data: Zoi.map() |> Zoi.optional(),
              repair_result: Zoi.tuple({Zoi.enum([:ok, :error]), Zoi.any()}) |> Zoi.optional(),
              active_tools: Zoi.list(Zoi.map()) |> Zoi.optional(),
              pending_queries: Zoi.list(Zoi.map()) |> Zoi.optional(),
              termination_reason: Zoi.atom() |> Zoi.optional(),
              checkpoint_phase: Zoi.enum([:before_llm, :after_llm, :after_tools, :terminal]) |> Zoi.optional(),
              limit_result: Zoi.string() |> Zoi.optional(),
              batch: Zoi.list(Zoi.map()) |> Zoi.optional(),
              pending_batches: Zoi.list(Zoi.list(Zoi.map())) |> Zoi.optional(),
              tool_results: Zoi.list(Zoi.map()) |> Zoi.optional(),
              adaptive: Zoi.map() |> Zoi.optional(),
              tree_search: Zoi.map() |> Zoi.optional(),
              graph_search: Zoi.struct(Jido.AI.Reasoning.GraphOfThoughts.Machine) |> Zoi.optional(),
              recursive: Zoi.struct(Jido.AI.Reasoning.TRM.Machine) |> Zoi.optional()
            },
            unrecognized_keys: :error
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  def schema, do: @schema

  def new(values) when is_map(values) do
    defaults = %{
      request_id: Jido.Signal.ID.generate!(),
      run_id: Jido.Signal.ID.generate!(),
      started_at_ms: System.system_time(:millisecond),
      iterations: 0,
      model_calls: 0,
      tool_calls: 0,
      repairs: 0,
      usage: %{}
    }

    validate(Map.merge(defaults, values))
  end

  def validate(value), do: Zoi.parse(@schema, value)

  # Position of the model call, not a second counter. Repairs reuse the
  # current reasoning iteration, while a new model/tool round advances it.
  def model_iteration(state) do
    if state.repairs > 0 or state[:checkpoint_phase] == :after_llm,
      do: max(state.iterations, 1),
      else: state.iterations + 1
  end

  def iteration(state, phase) do
    if phase in [:before_llm, :after_tools] or state[:termination_reason] == :max_iterations,
      do: state.iterations + 1,
      else: max(state.iterations, 1)
  end
end
