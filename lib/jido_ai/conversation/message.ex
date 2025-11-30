defmodule Jido.AI.Conversation.Message do
  @moduledoc """
  Represents a message in a conversation.

  Messages can be from different roles:
  - `:system` - System instructions
  - `:user` - User input
  - `:assistant` - LLM response
  - `:tool` - Tool execution result
  """

  use TypedStruct

  typedstruct do
    @typedoc "A conversation message"

    field :id, String.t(), enforce: true
    field :role, :system | :user | :assistant | :tool, enforce: true
    field :content, String.t(), default: ""
    field :tool_calls, list(map()), default: []
    field :tool_call_id, String.t()
    field :name, String.t()
    field :timestamp, DateTime.t(), enforce: true
  end

  @doc """
  Creates a new message with the given role and content.

  ## Examples

      iex> Message.new(:user, "Hello!")
      %Message{role: :user, content: "Hello!", ...}

      iex> Message.new(:assistant, "Hi there!", tool_calls: [%{name: "search", ...}])
      %Message{role: :assistant, content: "Hi there!", tool_calls: [...], ...}
  """
  @spec new(atom(), String.t(), keyword()) :: t()
  def new(role, content, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      role: role,
      content: content,
      tool_calls: Keyword.get(opts, :tool_calls, []),
      tool_call_id: Keyword.get(opts, :tool_call_id),
      name: Keyword.get(opts, :name),
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Creates a system message.
  """
  @spec system(String.t()) :: t()
  def system(content), do: new(:system, content)

  @doc """
  Creates a user message.
  """
  @spec user(String.t()) :: t()
  def user(content), do: new(:user, content)

  @doc """
  Creates an assistant message.
  """
  @spec assistant(String.t(), keyword()) :: t()
  def assistant(content, opts \\ []), do: new(:assistant, content, opts)

  @doc """
  Creates a tool result message.
  """
  @spec tool(String.t(), String.t(), String.t()) :: t()
  def tool(content, tool_call_id, name) do
    new(:tool, content, tool_call_id: tool_call_id, name: name)
  end

  @doc """
  Converts a message to the format expected by ReqLLM.
  """
  @spec to_llm_format(t()) :: map()
  def to_llm_format(%__MODULE__{} = message) do
    base = %{
      role: to_string(message.role),
      content: message.content
    }

    base
    |> maybe_add_tool_calls(message)
    |> maybe_add_tool_call_id(message)
    |> maybe_add_name(message)
  end

  defp maybe_add_tool_calls(map, %{tool_calls: []}), do: map
  defp maybe_add_tool_calls(map, %{tool_calls: nil}), do: map
  defp maybe_add_tool_calls(map, %{tool_calls: calls}), do: Map.put(map, :tool_calls, calls)

  defp maybe_add_tool_call_id(map, %{tool_call_id: nil}), do: map
  defp maybe_add_tool_call_id(map, %{tool_call_id: id}), do: Map.put(map, :tool_call_id, id)

  defp maybe_add_name(map, %{name: nil}), do: map
  defp maybe_add_name(map, %{name: name}), do: Map.put(map, :name, name)

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
