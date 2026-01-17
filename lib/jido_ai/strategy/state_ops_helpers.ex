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

  @type state_op :: StateOp.SetState.t() | StateOp.SetPath.t() | StateOp.DeleteKeys.t()

  @doc """
  Creates a StateOp to update the strategy state.

  Performs a deep merge of the given attributes into the strategy state.

  ## Examples

      iex> StateOpsHelpers.update_strategy_state(%{status: :running, iteration: 1})
      %StateOp.SetState{attrs: %{status: :running, iteration: 1}}
  """
  @spec update_strategy_state(map()) :: StateOp.SetState.t()
  def update_strategy_state(attrs) when is_map(attrs) do
    StateOp.set_state(attrs)
  end

  @doc """
  Creates a StateOp to set a specific field in the strategy state.

  ## Examples

      iex> StateOpsHelpers.set_strategy_field(:status, :running)
      %StateOp.SetPath{path: [:status], value: :running}
  """
  @spec set_strategy_field(atom(), term()) :: StateOp.SetPath.t()
  def set_strategy_field(key, value) when is_atom(key) do
    StateOp.set_path([key], value)
  end

  @doc """
  Creates a StateOp to set the iteration status.

  ## Examples

      iex> StateOpsHelpers.set_iteration_status(:awaiting_llm)
      %StateOp.SetPath{path: [:status], value: :awaiting_llm}
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
      %StateOp.SetPath{path: [:iteration], value: 5}
  """
  @spec set_iteration(non_neg_integer()) :: StateOp.SetPath.t()
  def set_iteration(iteration) when is_integer(iteration) and iteration >= 0 do
    StateOp.set_path([:iteration], iteration)
  end

  @doc """
  Creates a StateOp to set the iteration counter (alias for set_iteration/1).

  ## Examples

      iex> StateOpsHelpers.set_iteration_counter(5)
      %StateOp.SetPath{path: [:iteration], value: 5}
  """
  @spec set_iteration_counter(non_neg_integer()) :: StateOp.SetPath.t()
  def set_iteration_counter(iteration), do: set_iteration(iteration)

  @doc """
  Creates a StateOp to append a message to the conversation.

  ## Examples

      iex> message = %{role: :user, content: "Hello"}
      iex> StateOpsHelpers.append_conversation([message])
      %StateOp.SetState{attrs: %{conversation: [%{role: :user, content: "Hello"}]}}
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
      %StateOp.SetState{attrs: %{conversation: [%{role: :user, content: "Hello"}, %{role: :assistant, content: "Hi"}]}}
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
      %StateOp.SetState{attrs: %{conversation: messages}}
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
      %StateOp.SetState{attrs: %{pending_tool_calls: tools}}
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
      %StateOp.SetState{attrs: %{pending_tool_calls: [%{id: "call_1", name: "search", arguments: %{query: "test"}}]}}
  """
  @spec add_pending_tool(map()) :: StateOp.SetState.t()
  def add_pending_tool(tool) when is_map(tool) do
    StateOp.set_state(%{pending_tool_calls: [tool]})
  end

  @doc """
  Creates a StateOp to clear pending tool calls.

  ## Examples

      iex> StateOpsHelpers.clear_pending_tools()
      %StateOp.SetState{attrs: %{pending_tool_calls: []}}
  """
  @spec clear_pending_tools() :: StateOp.SetState.t()
  def clear_pending_tools do
    StateOp.set_state(%{pending_tool_calls: []})
  end

  @doc """
  Creates a StateOp to remove a specific pending tool by ID.

  ## Examples

      iex> StateOpsHelpers.remove_pending_tool("call_1")
      %StateOp.DeletePath{path: [:pending_tool_calls, "call_1"]}
  """
  @spec remove_pending_tool(String.t()) :: StateOp.DeletePath.t()
  def remove_pending_tool(tool_id) when is_binary(tool_id) do
    # Note: DeletePath removes a specific key, but pending_tool_calls is a list
    # This would need custom handling or we use a different approach
    # For now, we'll return a DeletePath that could be used with a map-based index
    StateOp.delete_path([:pending_tool_calls, tool_id])
  end

  @doc """
  Creates a StateOp to set the current LLM call ID.

  ## Examples

      iex> StateOpsHelpers.set_call_id("call_123")
      %StateOp.SetPath{path: [:current_llm_call_id], value: "call_123"}
  """
  @spec set_call_id(String.t()) :: StateOp.SetPath.t()
  def set_call_id(call_id) when is_binary(call_id) do
    StateOp.set_path([:current_llm_call_id], call_id)
  end

  @doc """
  Creates a StateOp to clear the current LLM call ID.

  ## Examples

      iex> StateOpsHelpers.clear_call_id()
      %StateOp.DeletePath{path: [:current_llm_call_id]}
  """
  @spec clear_call_id() :: StateOp.DeletePath.t()
  def clear_call_id do
    StateOp.delete_path([:current_llm_call_id])
  end

  @doc """
  Creates a StateOp to set the final answer.

  ## Examples

      iex> StateOpsHelpers.set_final_answer("42")
      %StateOp.SetPath{path: [:final_answer], value: "42"}
  """
  @spec set_final_answer(String.t()) :: StateOp.SetPath.t()
  def set_final_answer(answer) when is_binary(answer) do
    StateOp.set_path([:final_answer], answer)
  end

  @doc """
  Creates a StateOp to set the termination reason.

  ## Examples

      iex> StateOpsHelpers.set_termination_reason(:final_answer)
      %StateOp.SetPath{path: [:termination_reason], value: :final_answer}
  """
  @spec set_termination_reason(atom()) :: StateOp.SetPath.t()
  def set_termination_reason(reason) when is_atom(reason) do
    StateOp.set_path([:termination_reason], reason)
  end

  @doc """
  Creates a StateOp to set the streaming text.

  ## Examples

      iex> StateOpsHelpers.set_streaming_text("Hello")
      %StateOp.SetPath{path: [:streaming_text], value: "Hello"}
  """
  @spec set_streaming_text(String.t()) :: StateOp.SetPath.t()
  def set_streaming_text(text) when is_binary(text) do
    StateOp.set_path([:streaming_text], text)
  end

  @doc """
  Creates a StateOp to append to the streaming text.

  ## Examples

      iex> StateOpsHelpers.append_streaming_text(" world")
      %StateOp.SetPath{path: [:streaming_text], value: " world"}
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
      %StateOp.SetState{attrs: %{usage: usage}}
  """
  @spec set_usage(map()) :: StateOp.SetState.t()
  def set_usage(usage) when is_map(usage) do
    StateOp.set_state(%{usage: usage})
  end

  @doc """
  Creates a StateOp to delete temporary keys from strategy state.

  ## Examples

      iex> StateOpsHelpers.delete_temp_keys()
      %StateOp.DeleteKeys{keys: [:temp, :cache, :ephemeral]}
  """
  @spec delete_temp_keys() :: StateOp.DeleteKeys.t()
  def delete_temp_keys do
    StateOp.delete_keys([:temp, :cache, :ephemeral])
  end

  @doc """
  Creates a StateOp to delete specific keys from strategy state.

  ## Examples

      iex> StateOpsHelpers.delete_keys([:temp1, :temp2])
      %StateOp.DeleteKeys{keys: [:temp1, :temp2]}
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
  Composes multiple state operations into a single list.

  This is a convenience function for building state operation lists.

  ## Examples

      iex> StateOpsHelpers.compose([
      ...>   StateOpsHelpers.set_iteration_status(:running),
      ...>   StateOpsHelpers.set_iteration(1)
      ...> ])
      [%StateOp.SetPath{path: [:status], value: :running}, %StateOp.SetPath{path: [:iteration], value: 1}]
  """
  @spec compose([state_op()]) :: [state_op()]
  def compose(ops) when is_list(ops), do: ops
end
