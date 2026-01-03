defmodule Jido.AI.ReAct.Machine do
  @moduledoc """
  Pure state machine for the ReAct (Reason-Act) pattern.

  This module implements the core state transitions for a ReAct agent without
  any side effects. It uses Fsmx for state machine management and returns
  directives that describe what external effects should be performed.

  ## States

  - `:idle` - Initial state, waiting for a user query
  - `:awaiting_llm` - Waiting for LLM response
  - `:awaiting_tool` - Waiting for tool execution results
  - `:completed` - Final state, conversation complete
  - `:error` - Error state

  ## Usage

  The machine is used by the ReAct strategy:

      machine = Machine.new(config)
      {machine, directives} = Machine.update(machine, {:start, query, call_id})

  All state transitions are pure - side effects are described in directives.
  """

  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "idle" => ["awaiting_llm"],
      "awaiting_llm" => ["awaiting_tool", "completed", "error"],
      "awaiting_tool" => ["awaiting_llm", "completed", "error"],
      "completed" => [],
      "error" => []
    }

  @type status :: :idle | :awaiting_llm | :awaiting_tool | :completed | :error
  @type termination_reason :: :final_answer | :max_iterations | :error | nil

  @type pending_tool_call :: %{
          id: String.t(),
          name: String.t(),
          arguments: map(),
          result: term() | nil
        }

  @type t :: %__MODULE__{
          status: String.t(),
          iteration: non_neg_integer(),
          conversation: list(),
          pending_tool_calls: [pending_tool_call()],
          result: term(),
          current_llm_call_id: String.t() | nil,
          termination_reason: termination_reason(),
          streaming_text: String.t(),
          streaming_thinking: String.t()
        }

  defstruct status: "idle",
            iteration: 0,
            conversation: [],
            pending_tool_calls: [],
            result: nil,
            current_llm_call_id: nil,
            termination_reason: nil,
            streaming_text: "",
            streaming_thinking: ""

  @type msg ::
          {:start, query :: String.t(), call_id :: String.t()}
          | {:llm_result, call_id :: String.t(), result :: term()}
          | {:llm_partial, call_id :: String.t(), delta :: String.t(), chunk_type :: atom()}
          | {:tool_result, call_id :: String.t(), result :: term()}

  @type directive ::
          {:call_llm_stream, id :: String.t(), context :: list()}
          | {:exec_tool, id :: String.t(), tool_name :: String.t(), arguments :: map()}

  @doc """
  Creates a new machine in the idle state.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Updates the machine state based on a message.

  Returns the updated machine and a list of directives describing
  external effects to be performed.

  ## Messages

  - `{:start, query, call_id}` - Start a new conversation
  - `{:llm_result, call_id, result}` - Handle LLM response
  - `{:llm_partial, call_id, delta, chunk_type}` - Handle streaming chunk
  - `{:tool_result, call_id, result}` - Handle tool execution result

  ## Directives

  - `{:call_llm_stream, id, context}` - Request LLM call
  - `{:exec_tool, id, tool_name, arguments}` - Request tool execution
  """
  @spec update(t(), msg(), map()) :: {t(), [directive()]}
  def update(machine, msg, env \\ %{})

  def update(%__MODULE__{status: "idle"} = machine, {:start, query, call_id}, env) do
    system_prompt = Map.fetch!(env, :system_prompt)
    conversation = [system_message(system_prompt), user_message(query)]

    with_transition(machine, "awaiting_llm", fn machine ->
      machine =
        machine
        |> Map.put(:iteration, 1)
        |> Map.put(:conversation, conversation)
        |> Map.put(:pending_tool_calls, [])
        |> Map.put(:result, nil)
        |> Map.put(:termination_reason, nil)
        |> Map.put(:current_llm_call_id, call_id)
        |> Map.put(:streaming_text, "")
        |> Map.put(:streaming_thinking, "")

      {machine, [{:call_llm_stream, call_id, conversation}]}
    end)
  end

  def update(%__MODULE__{status: "awaiting_llm"} = machine, {:llm_result, call_id, result}, env) do
    if call_id != machine.current_llm_call_id do
      {machine, []}
    else
      handle_llm_response(machine, result, env)
    end
  end

  def update(
        %__MODULE__{status: "awaiting_llm"} = machine,
        {:llm_partial, call_id, delta, chunk_type},
        _env
      ) do
    if call_id != machine.current_llm_call_id do
      {machine, []}
    else
      machine =
        case chunk_type do
          :content ->
            Map.update!(machine, :streaming_text, &(&1 <> delta))

          :thinking ->
            Map.update!(machine, :streaming_thinking, &(&1 <> delta))

          _ ->
            machine
        end

      {machine, []}
    end
  end

  def update(%__MODULE__{status: "awaiting_tool"} = machine, {:tool_result, call_id, result}, env) do
    max_iterations = Map.get(env, :max_iterations, 10)
    {machine, all_complete?} = record_tool_result(machine, call_id, result)

    if all_complete? do
      machine =
        machine
        |> append_all_tool_results()
        |> inc_iteration()

      cond do
        machine.iteration > max_iterations ->
          with_transition(machine, "completed", fn machine ->
            machine =
              machine
              |> Map.put(:termination_reason, :max_iterations)
              |> Map.put(:result, "Maximum iterations reached without a final answer.")

            {machine, []}
          end)

        true ->
          new_call_id = generate_call_id()

          with_transition(machine, "awaiting_llm", fn machine ->
            machine =
              machine
              |> Map.put(:current_llm_call_id, new_call_id)
              |> Map.put(:streaming_text, "")
              |> Map.put(:streaming_thinking, "")

            {machine, [{:call_llm_stream, new_call_id, machine.conversation}]}
          end)
      end
    else
      {machine, []}
    end
  end

  def update(machine, _msg, _env) do
    {machine, []}
  end

  @doc """
  Converts the machine state to a map suitable for strategy state storage.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = machine) do
    machine
    |> Map.from_struct()
    |> Map.update!(:status, &status_to_atom/1)
  end

  defp status_to_atom("idle"), do: :idle
  defp status_to_atom("awaiting_llm"), do: :awaiting_llm
  defp status_to_atom("awaiting_tool"), do: :awaiting_tool
  defp status_to_atom("completed"), do: :completed
  defp status_to_atom("error"), do: :error
  defp status_to_atom(status) when is_atom(status), do: status

  @doc """
  Creates a machine from a map (e.g., from strategy state storage).
  """
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map) do
    status =
      case map[:status] do
        s when is_atom(s) -> Atom.to_string(s)
        s when is_binary(s) -> s
        nil -> "idle"
      end

    %__MODULE__{
      status: status,
      iteration: map[:iteration] || 0,
      conversation: map[:conversation] || [],
      pending_tool_calls: map[:pending_tool_calls] || [],
      result: map[:result],
      current_llm_call_id: map[:current_llm_call_id],
      termination_reason: map[:termination_reason],
      streaming_text: map[:streaming_text] || "",
      streaming_thinking: map[:streaming_thinking] || ""
    }
  end

  # Private helpers

  defp with_transition(machine, new_status, fun) do
    case Fsmx.transition(machine, new_status, state_field: :status) do
      {:ok, machine} -> fun.(machine)
      {:error, _} -> {machine, []}
    end
  end

  defp handle_llm_response(machine, {:error, reason}, _env) do
    with_transition(machine, "error", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, :error)
        |> Map.put(:result, "Error: #{inspect(reason)}")

      {machine, []}
    end)
  end

  defp handle_llm_response(machine, {:ok, result}, env) do
    case result.type do
      :tool_calls -> handle_tool_calls(machine, result.tool_calls, env)
      :final_answer -> handle_final_answer(machine, result.text)
    end
  end

  defp handle_tool_calls(machine, tool_calls, _env) do
    assistant_msg = assistant_tool_calls_message(tool_calls)

    pending =
      Enum.map(tool_calls, fn tc ->
        %{id: tc.id, name: tc.name, arguments: tc.arguments, result: nil}
      end)

    with_transition(machine, "awaiting_tool", fn machine ->
      machine =
        machine
        |> Map.update!(:conversation, &(&1 ++ [assistant_msg]))
        |> Map.put(:pending_tool_calls, pending)

      directives =
        Enum.map(tool_calls, fn tc ->
          {:exec_tool, tc.id, tc.name, tc.arguments}
        end)

      {machine, directives}
    end)
  end

  defp handle_final_answer(machine, answer) do
    assistant_msg = assistant_message(answer)

    with_transition(machine, "completed", fn machine ->
      machine =
        machine
        |> Map.put(:termination_reason, :final_answer)
        |> Map.update!(:conversation, &(&1 ++ [assistant_msg]))
        |> Map.put(:result, answer)

      {machine, []}
    end)
  end

  defp record_tool_result(machine, call_id, result) do
    pending =
      Enum.map(machine.pending_tool_calls, fn tc ->
        if tc.id == call_id, do: %{tc | result: result}, else: tc
      end)

    all_complete? = Enum.all?(pending, &(&1.result != nil))
    {%{machine | pending_tool_calls: pending}, all_complete?}
  end

  defp append_all_tool_results(machine) do
    tool_msgs = Enum.map(machine.pending_tool_calls, &tool_result_message/1)

    machine
    |> Map.update!(:conversation, &(&1 ++ tool_msgs))
    |> Map.put(:pending_tool_calls, [])
  end

  defp inc_iteration(machine), do: Map.update!(machine, :iteration, &(&1 + 1))

  @doc """
  Generates a unique call ID for LLM requests.
  """
  @spec generate_call_id() :: String.t()
  def generate_call_id do
    "call_#{Jido.Util.generate_id()}"
  end

  # Message builders - these create simple maps that can be converted to ReqLLM messages
  # by the strategy layer

  defp system_message(content), do: %{role: :system, content: content}
  defp user_message(content), do: %{role: :user, content: content}
  defp assistant_message(content), do: %{role: :assistant, content: content}

  defp assistant_tool_calls_message(tool_calls) do
    %{
      role: :assistant,
      content: "",
      tool_calls:
        Enum.map(tool_calls, fn tc ->
          %{id: tc.id, name: tc.name, arguments: tc.arguments}
        end)
    }
  end

  defp tool_result_message(%{id: id, name: name, result: result}) do
    content =
      case result do
        {:ok, res} -> Jason.encode!(res)
        {:error, reason} -> Jason.encode!(%{error: "Error: #{inspect(reason)}"})
      end

    %{role: :tool, tool_call_id: id, name: name, content: content}
  end
end
