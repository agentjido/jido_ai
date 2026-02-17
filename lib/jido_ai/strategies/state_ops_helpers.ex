defmodule Jido.AI.Strategy.StateOpsHelpers do
  @moduledoc """
  Helper functions for creating StateOps in Jido.AI strategies.

  This module provides convenient helpers for common state operation patterns
  used across strategies. It wraps `Jido.Agent.StateOp` constructors with
  strategy-specific semantics.

  ## StateOp Types

  * `SetState` - Deep merge attributes into state
  * `SetPath` - Set value at nested path
  * `DeleteKeys` - Remove top-level keys
  * `DeletePath` - Delete value at nested path

  ## Usage

      state_ops = [
        StateOpsHelpers.set_strategy_status(:running),
        StateOpsHelpers.increment_iteration(),
        StateOpsHelpers.append_to_conversation(message)
      ]

  """

  alias Jido.Agent.StateOp

  @type state_op ::
          StateOp.SetState.t() | StateOp.SetPath.t() | StateOp.DeleteKeys.t() | StateOp.DeletePath.t()

  @doc """
  Creates a StateOp to update the strategy state.

  Performs a deep merge of the given attributes into the strategy state.

  ## Examples

      iex> StateOpsHelpers.update_strategy_state(%{status: :running, iteration: 1})
      %Jido.Agent.StateOp.SetState{attrs: %{status: :running, iteration: 1}}
  """
  @spec update_strategy_state(map()) :: StateOp.SetState.t()
  def update_strategy_state(attrs) when is_map(attrs) do
    StateOp.set_state(attrs)
  end

  @doc """
  Creates a StateOp to set a specific field in the strategy state.

  ## Examples

      iex> StateOpsHelpers.set_strategy_field(:status, :running)
      %Jido.Agent.StateOp.SetPath{path: [:status], value: :running}
  """
  @spec set_strategy_field(atom(), term()) :: StateOp.SetPath.t()
  def set_strategy_field(key, value) when is_atom(key) do
    StateOp.set_path([key], value)
  end

  @doc """
  Creates a StateOp to set the iteration status.

  ## Examples

      iex> StateOpsHelpers.set_iteration_status(:awaiting_llm)
      %Jido.Agent.StateOp.SetPath{path: [:status], value: :awaiting_llm}
  """
  @spec set_iteration_status(atom()) :: StateOp.SetPath.t()
  def set_iteration_status(status) when is_atom(status) do
    set_strategy_field(:status, status)
  end

  @doc """
  Creates a StateOp to increment the iteration counter.

  Note: This cannot directly read the current value, so it should be used
  with the current iteration value known from context.

  ## Examples

      iex> StateOpsHelpers.set_iteration(5)
      %Jido.Agent.StateOp.SetPath{path: [:iteration], value: 5}
  """
  @spec set_iteration(non_neg_integer()) :: StateOp.SetPath.t()
  def set_iteration(iteration) when is_integer(iteration) and iteration >= 0 do
    StateOp.set_path([:iteration], iteration)
  end

  @doc """
  Creates a StateOp to append a message to the conversation.

  ## Examples

      iex> message = %{role: :user, content: "Hello"}
      iex> StateOpsHelpers.append_conversation([message])
      %Jido.Agent.StateOp.SetState{attrs: %{conversation: [%{role: :user, content: "Hello"}]}}
  """
  @spec append_conversation([map()]) :: StateOp.SetState.t()
  def append_conversation(messages) when is_list(messages) do
    StateOp.set_state(%{conversation: messages})
  end

  @doc """
  Creates a StateOp to prepend a message to the conversation.

  ## Examples

      iex> message = %{role: :user, content: "Hello"}
      iex> current_conversation = [%{role: :assistant, content: "Hi"}]
      iex> StateOpsHelpers.prepend_conversation(message, current_conversation)
      %Jido.Agent.StateOp.SetState{attrs: %{conversation: [%{role: :user, content: "Hello"}, %{role: :assistant, content: "Hi"}]}}
  """
  @spec prepend_conversation(map(), [map()]) :: StateOp.SetState.t()
  def prepend_conversation(message, existing_conversation \\ [])
      when is_map(message) and is_list(existing_conversation) do
    StateOp.set_state(%{conversation: [message | existing_conversation]})
  end

  @doc """
  Creates a StateOp to set the entire conversation.

  ## Examples

      iex> messages = [%{role: :user, content: "Hello"}, %{role: :assistant, content: "Hi"}]
      iex> StateOpsHelpers.set_conversation(messages)
      %Jido.Agent.StateOp.SetState{attrs: %{conversation: messages}}
  """
  @spec set_conversation([map()]) :: StateOp.SetState.t()
  def set_conversation(messages) when is_list(messages) do
    StateOp.set_state(%{conversation: messages})
  end

  @doc """
  Creates a StateOp to set pending tool calls.

  ## Examples

      iex> tools = [%{id: "call_1", name: "search", arguments: %{query: "test"}}]
      iex> StateOpsHelpers.set_pending_tools(tools)
      %Jido.Agent.StateOp.SetState{attrs: %{pending_tool_calls: tools}}
  """
  @spec set_pending_tools([map()]) :: StateOp.SetState.t()
  def set_pending_tools(tools) when is_list(tools) do
    StateOp.set_state(%{pending_tool_calls: tools})
  end

  @doc """
  Creates a StateOp to add a pending tool call.

  ## Examples

      iex> tool = %{id: "call_1", name: "search", arguments: %{query: "test"}}
      iex> StateOpsHelpers.add_pending_tool(tool)
      %Jido.Agent.StateOp.SetState{attrs: %{pending_tool_calls: [%{id: "call_1", name: "search", arguments: %{query: "test"}}]}}
  """
  @spec add_pending_tool(map()) :: StateOp.SetState.t()
  def add_pending_tool(tool) when is_map(tool) do
    StateOp.set_state(%{pending_tool_calls: [tool]})
  end

  @doc """
  Creates a StateOp to clear pending tool calls.

  ## Examples

      iex> StateOpsHelpers.clear_pending_tools()
      %Jido.Agent.StateOp.SetState{attrs: %{pending_tool_calls: []}}
  """
  @spec clear_pending_tools() :: StateOp.SetState.t()
  def clear_pending_tools do
    StateOp.set_state(%{pending_tool_calls: []})
  end

  @doc """
  Creates a StateOp to remove a specific pending tool by ID.

  ## Examples

      iex> StateOpsHelpers.remove_pending_tool("call_1")
      %Jido.Agent.StateOp.DeletePath{path: [:pending_tool_calls, "call_1"]}

  Note: This operation is meant for map-based pending_tool_calls.
  For list-based pending_tool_calls, use filter_pending_tools/1 instead.
  """
  @spec remove_pending_tool(String.t()) :: StateOp.DeletePath.t()
  def remove_pending_tool(tool_id) when is_binary(tool_id) do
    # Construct DeletePath struct directly to avoid dialyzer warning about
    # mixing atoms and strings in the path (which DeletePath schema expects to be all atoms)
    %StateOp.DeletePath{path: [:pending_tool_calls, tool_id]}
  end

  @doc """
  Creates a StateOp to set the current LLM call ID.

  ## Examples

      iex> StateOpsHelpers.set_call_id("call_123")
      %Jido.Agent.StateOp.SetPath{path: [:current_llm_call_id], value: "call_123"}
  """
  @spec set_call_id(String.t()) :: StateOp.SetPath.t()
  def set_call_id(call_id) when is_binary(call_id) do
    StateOp.set_path([:current_llm_call_id], call_id)
  end

  @doc """
  Creates a StateOp to clear the current LLM call ID.

  ## Examples

      iex> StateOpsHelpers.clear_call_id()
      %Jido.Agent.StateOp.DeletePath{path: [:current_llm_call_id]}
  """
  @spec clear_call_id() :: StateOp.DeletePath.t()
  def clear_call_id do
    StateOp.delete_path([:current_llm_call_id])
  end

  @doc """
  Creates a StateOp to set the final answer.

  ## Examples

      iex> StateOpsHelpers.set_final_answer("42")
      %Jido.Agent.StateOp.SetPath{path: [:final_answer], value: "42"}
  """
  @spec set_final_answer(String.t()) :: StateOp.SetPath.t()
  def set_final_answer(answer) when is_binary(answer) do
    StateOp.set_path([:final_answer], answer)
  end

  @doc """
  Creates a StateOp to set the termination reason.

  ## Examples

      iex> StateOpsHelpers.set_termination_reason(:final_answer)
      %Jido.Agent.StateOp.SetPath{path: [:termination_reason], value: :final_answer}
  """
  @spec set_termination_reason(atom()) :: StateOp.SetPath.t()
  def set_termination_reason(reason) when is_atom(reason) do
    StateOp.set_path([:termination_reason], reason)
  end

  @doc """
  Creates a StateOp to set the streaming text.

  ## Examples

      iex> StateOpsHelpers.set_streaming_text("Hello")
      %Jido.Agent.StateOp.SetPath{path: [:streaming_text], value: "Hello"}
  """
  @spec set_streaming_text(String.t()) :: StateOp.SetPath.t()
  def set_streaming_text(text) when is_binary(text) do
    StateOp.set_path([:streaming_text], text)
  end

  @doc """
  Creates a StateOp to append to the streaming text.

  ## Examples

      iex> StateOpsHelpers.append_streaming_text(" world")
      %Jido.Agent.StateOp.SetPath{path: [:streaming_text], value: " world"}
  """
  @spec append_streaming_text(String.t()) :: StateOp.SetPath.t()
  def append_streaming_text(text) when is_binary(text) do
    StateOp.set_path([:streaming_text], text)
  end

  @doc """
  Creates a StateOp to set the usage metadata.

  ## Examples

      iex> usage = %{input_tokens: 10, output_tokens: 20}
      iex> StateOpsHelpers.set_usage(usage)
      %Jido.Agent.StateOp.SetState{attrs: %{usage: usage}}
  """
  @spec set_usage(map()) :: StateOp.SetState.t()
  def set_usage(usage) when is_map(usage) do
    StateOp.set_state(%{usage: usage})
  end

  @doc """
  Creates a StateOp to delete temporary keys from strategy state.

  ## Examples

      iex> StateOpsHelpers.delete_temp_keys()
      %Jido.Agent.StateOp.DeleteKeys{keys: [:temp, :cache, :ephemeral]}
  """
  @spec delete_temp_keys() :: StateOp.DeleteKeys.t()
  def delete_temp_keys do
    StateOp.delete_keys([:temp, :cache, :ephemeral])
  end

  @doc """
  Creates a StateOp to delete specific keys from strategy state.

  ## Examples

      iex> StateOpsHelpers.delete_keys([:temp1, :temp2])
      %Jido.Agent.StateOp.DeleteKeys{keys: [:temp1, :temp2]}
  """
  @spec delete_keys([atom()]) :: StateOp.DeleteKeys.t()
  def delete_keys(keys) when is_list(keys) do
    StateOp.delete_keys(keys)
  end

  @doc """
  Creates a StateOp to reset the strategy state to initial values.

  ## Examples

      iex> result = StateOpsHelpers.reset_strategy_state()
      iex> result.state.status == :idle and result.state.iteration == 0
      true
  """
  @spec reset_strategy_state() :: StateOp.ReplaceState.t()
  def reset_strategy_state do
    StateOp.replace_state(%{
      status: :idle,
      iteration: 0,
      conversation: [],
      pending_tool_calls: [],
      final_answer: nil,
      current_llm_call_id: nil,
      termination_reason: nil
    })
  end

  @doc """
  Creates a StateOp to update the config field in strategy state.

  ## Examples

      iex> config = %{tools: [], model: "test"}
      iex> StateOpsHelpers.update_config(config)
      %Jido.Agent.StateOp.SetState{attrs: %{config: config}}
  """
  @spec update_config(map()) :: StateOp.SetState.t()
  def update_config(config) when is_map(config) do
    StateOp.set_state(%{config: config})
  end

  @doc """
  Creates a StateOp to set a specific config field.

  ## Examples

      iex> StateOpsHelpers.set_config_field(:tools, [MyAction])
      %Jido.Agent.StateOp.SetPath{path: [:config, :tools], value: [MyAction]}
  """
  @spec set_config_field(atom(), term()) :: StateOp.SetPath.t()
  def set_config_field(key, value) when is_atom(key) do
    StateOp.set_path([:config, key], value)
  end

  @doc """
  Creates StateOps to update multiple config fields at once.

  ## Examples

      iex> ops = StateOpsHelpers.update_config_fields(%{tools: [], model: "test"})
      iex> length(ops)
      2
      iex> hd(ops).path
      [:config, :tools]
  """
  @spec update_config_fields(map()) :: [StateOp.SetPath.t()]
  def update_config_fields(fields) when is_map(fields) do
    Enum.map(fields, fn {key, value} ->
      StateOp.set_path([:config, key], value)
    end)
  end

  @doc """
  Creates StateOps to update tools, actions_by_name, and reqllm_tools together.

  This is a common pattern when registering/unregistering tools.

  ## Examples

      iex> tools = [SomeAction]
      iex> actions_by_name = %{"action" => SomeAction}
      iex> reqllm_tools = [%{name: "action"}]
      iex> ops = StateOpsHelpers.update_tools_config(tools, actions_by_name, reqllm_tools)
      iex> length(ops)
      3
      iex> hd(ops).path
      [:config, :tools]
  """
  @spec update_tools_config([module()], %{String.t() => module()}, [map()]) :: [StateOp.SetPath.t()]
  def update_tools_config(tools, actions_by_name, reqllm_tools) do
    [
      StateOp.set_path([:config, :tools], tools),
      StateOp.set_path([:config, :actions_by_name], actions_by_name),
      StateOp.set_path([:config, :reqllm_tools], reqllm_tools)
    ]
  end

  @doc """
  Composes multiple state operations into a single list.

  This is a convenience function for building state operation lists.

  ## Examples

      iex> StateOpsHelpers.compose([
      ...>   StateOpsHelpers.set_iteration_status(:running),
      ...>   StateOpsHelpers.set_iteration(1)
      ...> ])
      [%Jido.Agent.StateOp.SetPath{path: [:status], value: :running}, %Jido.Agent.StateOp.SetPath{path: [:iteration], value: 1}]
  """
  @spec compose([state_op()]) :: [state_op()]
  def compose(ops) when is_list(ops), do: ops

  @doc """
  Applies state operations to a state map.

  This is useful for strategies to apply state operations internally
  before setting the strategy state on the agent.

  ## Examples

      iex> ops = [Jido.Agent.StateOp.set_path([:status], :running)]
      iex> StateOpsHelpers.apply_to_state(%{iteration: 1}, ops)
      %{iteration: 1, status: :running}
  """
  @spec apply_to_state(map(), [state_op()]) :: map()
  def apply_to_state(state, ops) when is_list(ops) do
    Enum.reduce(ops, state, fn
      %Jido.Agent.StateOp.SetState{attrs: attrs}, acc ->
        deep_merge(acc, attrs)

      %Jido.Agent.StateOp.ReplaceState{state: new_state}, _acc ->
        new_state

      %Jido.Agent.StateOp.DeleteKeys{keys: keys}, acc ->
        Map.drop(acc, keys)

      %Jido.Agent.StateOp.SetPath{path: path, value: value}, acc ->
        deep_put_in(acc, path, value)

      %Jido.Agent.StateOp.DeletePath{path: path}, acc ->
        {_, result} = pop_in(acc, path)
        result
    end)
  end

  # Deep merge for nested maps
  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _k, lv, rv ->
      if is_map(lv) and is_map(rv) do
        deep_merge(lv, rv)
      else
        rv
      end
    end)
  end

  # Deep put_in for nested paths
  defp deep_put_in(map, [key], value) do
    Map.put(map, key, value)
  end

  defp deep_put_in(map, [key | rest], value) do
    nested = Map.get(map, key, %{})
    Map.put(map, key, deep_put_in(nested, rest, value))
  end
end
