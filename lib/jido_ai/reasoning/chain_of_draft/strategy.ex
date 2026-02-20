defmodule Jido.AI.Reasoning.ChainOfDraft.Strategy do
  @moduledoc """
  Chain-of-Draft strategy implemented as a thin wrapper over delegated CoT runtime.

  CoD reuses CoT worker orchestration (`ai.cot.worker.*`) and only changes the
  public query signal/action surface plus default prompt contract.
  """

  use Jido.Agent.Strategy

  alias Jido.AI.Reasoning.ChainOfDraft
  alias Jido.AI.Reasoning.ChainOfThought.Strategy, as: ChainOfThought

  @start :cod_start
  @llm_result :cod_llm_result
  @llm_partial :cod_llm_partial
  @request_error :cod_request_error
  @worker_event :cod_worker_event
  @worker_child_started :cod_worker_child_started
  @worker_child_exit :cod_worker_child_exit

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string(), request_id: Zoi.string() |> Zoi.optional()}),
      doc: "Start a delegated Chain-of-Draft reasoning session",
      name: "cod.start"
    },
    @request_error => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom(),
          message: Zoi.string()
        }),
      doc: "Handle rejected request lifecycle event",
      name: "cod.request_error"
    },
    @worker_event => %{
      schema: Zoi.object(%{request_id: Zoi.string(), event: Zoi.map()}),
      doc: "Handle delegated CoD worker runtime event envelopes",
      name: "ai.cot.worker.event"
    },
    @worker_child_started => %{
      schema:
        Zoi.object(%{
          parent_id: Zoi.string() |> Zoi.optional(),
          child_id: Zoi.string() |> Zoi.optional(),
          child_module: Zoi.any() |> Zoi.optional(),
          tag: Zoi.any(),
          pid: Zoi.any(),
          meta: Zoi.map() |> Zoi.default(%{})
        }),
      doc: "Handle CoD worker child started lifecycle signal",
      name: "jido.agent.child.started"
    },
    @worker_child_exit => %{
      schema:
        Zoi.object(%{
          tag: Zoi.any(),
          pid: Zoi.any(),
          reason: Zoi.any()
        }),
      doc: "Handle CoD worker child exit lifecycle signal",
      name: "jido.agent.child.exit"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Legacy no-op in delegated CoD mode",
      name: "cod.llm_result"
    },
    @llm_partial => %{
      schema:
        Zoi.object(%{
          call_id: Zoi.string(),
          delta: Zoi.string(),
          chunk_type: Zoi.atom() |> Zoi.default(:content)
        }),
      doc: "Legacy no-op in delegated CoD mode",
      name: "cod.llm_partial"
    }
  }

  @doc "Returns the action atom for starting a CoD reasoning session."
  @spec start_action() :: :cod_start
  def start_action, do: @start

  @doc "Returns the legacy action atom for handling LLM results."
  @spec llm_result_action() :: :cod_llm_result
  def llm_result_action, do: @llm_result

  @doc "Returns the legacy action atom for handling streaming LLM partial tokens."
  @spec llm_partial_action() :: :cod_llm_partial
  def llm_partial_action, do: @llm_partial

  @doc "Returns the action atom for handling request rejection events."
  @spec request_error_action() :: :cod_request_error
  def request_error_action, do: @request_error

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.cod.query", {:strategy_cmd, @start}},
      {"ai.cot.worker.event", {:strategy_cmd, @worker_event}},
      {"jido.agent.child.started", {:strategy_cmd, @worker_child_started}},
      {"jido.agent.child.exit", {:strategy_cmd, @worker_child_exit}},
      {"ai.request.error", {:strategy_cmd, @request_error}},
      {"ai.request.started", Jido.Actions.Control.Noop},
      {"ai.request.completed", Jido.Actions.Control.Noop},
      {"ai.request.failed", Jido.Actions.Control.Noop},
      {"ai.llm.delta", Jido.Actions.Control.Noop},
      {"ai.llm.response", Jido.Actions.Control.Noop},
      {"ai.usage", Jido.Actions.Control.Noop}
    ]
  end

  @impl true
  def snapshot(agent, ctx), do: ChainOfThought.snapshot(agent, ctx)

  @impl true
  def init(agent, ctx) do
    strategy_opts = Map.get(ctx, :strategy_opts, [])
    strategy_opts = Keyword.put_new(strategy_opts, :system_prompt, ChainOfDraft.default_system_prompt())
    ChainOfThought.init(agent, Map.put(ctx, :strategy_opts, strategy_opts))
  end

  @impl true
  def cmd(agent, instructions, ctx) do
    instructions = Enum.map(instructions, &map_instruction/1)
    ChainOfThought.cmd(agent, instructions, ctx)
  end

  @doc """
  Returns the extracted reasoning steps from the agent's current state.
  """
  @spec get_steps(Jido.Agent.t()) :: [Jido.AI.Reasoning.ChainOfThought.Machine.step()]
  defdelegate get_steps(agent), to: ChainOfThought

  @doc """
  Returns the conclusion from the agent's current state.
  """
  @spec get_conclusion(Jido.Agent.t()) :: String.t() | nil
  defdelegate get_conclusion(agent), to: ChainOfThought

  @doc """
  Returns the raw LLM response from the agent's current state.
  """
  @spec get_raw_response(Jido.Agent.t()) :: String.t() | nil
  defdelegate get_raw_response(agent), to: ChainOfThought

  defp map_instruction(%Jido.Instruction{} = instruction) do
    %{instruction | action: map_action(instruction.action)}
  end

  defp map_instruction(other), do: other

  defp map_action({action, meta}) when is_atom(action), do: {map_action(action), meta}
  defp map_action(@start), do: :cot_start
  defp map_action(@llm_result), do: :cot_llm_result
  defp map_action(@llm_partial), do: :cot_llm_partial
  defp map_action(@request_error), do: :cot_request_error
  defp map_action(@worker_event), do: :cot_worker_event
  defp map_action(@worker_child_started), do: :cot_worker_child_started
  defp map_action(@worker_child_exit), do: :cot_worker_child_exit
  defp map_action(other), do: other
end
