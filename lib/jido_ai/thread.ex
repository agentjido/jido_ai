defmodule Jido.AI.Thread do
  @moduledoc """
  Simple conversation thread that accumulates messages for LLM context projection.

  A minimal thread implementation that stores conversation history and projects it
  directly to ReqLLM message format. No policies, no windowing, no snapshots - just
  append and project.

  ## Design Principle

  **Thread = List of Messages. Projection = Thread + System Prompt.**

  ## Usage

      # Create a new thread
      thread = Thread.new(system_prompt: "You are helpful.")

      # Accumulate messages
      thread = thread
        |> Thread.append_user("Hello!")
        |> Thread.append_assistant("Hi there!")

      # Project to ReqLLM format
      messages = Thread.to_messages(thread)

  ## Multi-turn Conversations

  The thread accumulates the full conversation history, enabling multi-turn
  conversations where the LLM has access to prior context.
  """

  alias __MODULE__.Entry

  @type t :: %__MODULE__{
          id: String.t(),
          entries: [Entry.t()],
          system_prompt: String.t() | nil
        }

  defstruct [:id, entries: [], system_prompt: nil]

  defmodule Entry do
    @moduledoc """
    A single entry in a conversation thread.
    """

    @type t :: %__MODULE__{
            role: :user | :assistant | :tool | :system,
            content: String.t() | nil,
            tool_calls: list() | nil,
            tool_call_id: String.t() | nil,
            name: String.t() | nil,
            timestamp: DateTime.t() | nil
          }

    defstruct [:role, :content, :tool_calls, :tool_call_id, :name, :timestamp]
  end

  @doc """
  Create a new thread.

  ## Options

  - `:id` - Thread ID (auto-generated if not provided)
  - `:system_prompt` - System prompt to prepend to projected messages
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      system_prompt: Keyword.get(opts, :system_prompt)
    }
  end

  @doc """
  Append an entry to the thread.
  """
  @spec append(t(), Entry.t()) :: t()
  def append(%__MODULE__{} = thread, %Entry{} = entry) do
    entry = %{entry | timestamp: DateTime.utc_now()}
    %{thread | entries: thread.entries ++ [entry]}
  end

  @doc """
  Append a user message to the thread.
  """
  @spec append_user(t(), String.t()) :: t()
  def append_user(thread, content) when is_binary(content) do
    append(thread, %Entry{role: :user, content: content})
  end

  @doc """
  Append an assistant message to the thread, optionally with tool calls.
  """
  @spec append_assistant(t(), String.t() | nil, list() | nil) :: t()
  def append_assistant(thread, content, tool_calls \\ nil) do
    append(thread, %Entry{role: :assistant, content: content, tool_calls: tool_calls})
  end

  @doc """
  Append a tool result to the thread.
  """
  @spec append_tool_result(t(), String.t(), String.t(), String.t()) :: t()
  def append_tool_result(thread, tool_call_id, name, content) do
    append(thread, %Entry{role: :tool, tool_call_id: tool_call_id, name: name, content: content})
  end

  @doc """
  Project thread to ReqLLM message format.

  Returns a list of message maps suitable for passing to ReqLLM.

  ## Options

  - `:limit` - Maximum number of entries to include (takes last N, preserves system prompt)
  """
  @spec to_messages(t(), keyword()) :: [map()]
  def to_messages(%__MODULE__{} = thread, opts \\ []) do
    limit = Keyword.get(opts, :limit)

    entries =
      case limit do
        nil -> thread.entries
        n when is_integer(n) and n > 0 -> Enum.take(thread.entries, -n)
        _ -> thread.entries
      end

    messages = Enum.map(entries, &entry_to_message/1)

    case thread.system_prompt do
      nil -> messages
      prompt when is_binary(prompt) -> [%{role: :system, content: prompt} | messages]
    end
  end

  @doc """
  Convert a list of raw message maps to thread entries and append them.

  Useful for importing existing conversation history.
  """
  @spec append_messages(t(), [map()]) :: t()
  def append_messages(thread, messages) when is_list(messages) do
    Enum.reduce(messages, thread, fn msg, acc ->
      entry = message_to_entry(msg)
      append(acc, entry)
    end)
  end

  @doc """
  Count of entries in the thread.
  """
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{entries: entries}), do: Kernel.length(entries)

  @doc """
  Check if the thread is empty (no entries).
  """
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{entries: []}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  Clear all entries from the thread (keeps system prompt and ID).
  """
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = thread) do
    %{thread | entries: []}
  end

  @doc """
  Get the last entry in the thread.
  """
  @spec last_entry(t()) :: Entry.t() | nil
  def last_entry(%__MODULE__{entries: []}), do: nil
  def last_entry(%__MODULE__{entries: entries}), do: List.last(entries)

  @doc """
  Get the last assistant response content.
  """
  @spec last_assistant_content(t()) :: String.t() | nil
  def last_assistant_content(%__MODULE__{entries: entries}) do
    entries
    |> Enum.reverse()
    |> Enum.find(&(&1.role == :assistant))
    |> case do
      nil -> nil
      entry -> entry.content
    end
  end

  # Private helpers

  defp entry_to_message(%Entry{role: :user, content: content}) do
    %{role: :user, content: content}
  end

  defp entry_to_message(%Entry{role: :assistant, content: content, tool_calls: nil}) do
    %{role: :assistant, content: content}
  end

  defp entry_to_message(%Entry{role: :assistant, content: content, tool_calls: tool_calls}) do
    %{role: :assistant, content: content || "", tool_calls: tool_calls}
  end

  defp entry_to_message(%Entry{role: :tool, tool_call_id: id, name: name, content: content}) do
    %{role: :tool, tool_call_id: id, name: name, content: content}
  end

  defp entry_to_message(%Entry{role: :system, content: content}) do
    %{role: :system, content: content}
  end

  defp message_to_entry(%{role: role} = msg) do
    %Entry{
      role: normalize_role(role),
      content: Map.get(msg, :content),
      tool_calls: Map.get(msg, :tool_calls),
      tool_call_id: Map.get(msg, :tool_call_id),
      name: Map.get(msg, :name)
    }
  end

  defp normalize_role(:user), do: :user
  defp normalize_role(:assistant), do: :assistant
  defp normalize_role(:tool), do: :tool
  defp normalize_role(:system), do: :system
  defp normalize_role("user"), do: :user
  defp normalize_role("assistant"), do: :assistant
  defp normalize_role("tool"), do: :tool
  defp normalize_role("system"), do: :system

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
