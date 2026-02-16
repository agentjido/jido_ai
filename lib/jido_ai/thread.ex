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
            thinking: String.t() | nil,
            tool_calls: list() | nil,
            tool_call_id: String.t() | nil,
            name: String.t() | nil,
            timestamp: DateTime.t() | nil
          }

    defstruct [:role, :content, :thinking, :tool_calls, :tool_call_id, :name, :timestamp]
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

  If the entry already has a timestamp, it is preserved. Otherwise, the current
  UTC time is set.

  Note: Entries are stored in reverse order internally for O(1) append performance.
  They are reversed to chronological order when projected via `to_messages/2`.
  """
  @spec append(t(), Entry.t()) :: t()
  def append(%__MODULE__{} = thread, %Entry{} = entry) do
    entry = if entry.timestamp, do: entry, else: %{entry | timestamp: DateTime.utc_now()}
    %{thread | entries: [entry | thread.entries]}
  end

  @doc """
  Append a user message to the thread.
  """
  @spec append_user(t(), String.t()) :: t()
  def append_user(thread, content) when is_binary(content) do
    append(thread, %Entry{role: :user, content: content})
  end

  @doc """
  Append an assistant message to the thread, optionally with tool calls and thinking content.
  """
  @spec append_assistant(t(), String.t() | nil, list() | nil, keyword()) :: t()
  def append_assistant(thread, content, tool_calls \\ nil, opts \\ []) do
    thinking = Keyword.get(opts, :thinking)
    append(thread, %Entry{role: :assistant, content: content, tool_calls: tool_calls, thinking: thinking})
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

    # Entries are stored in reverse order, so reverse to get chronological order
    chronological = Enum.reverse(thread.entries)

    entries =
      case limit do
        nil -> chronological
        0 -> []
        n when is_integer(n) and n > 0 -> Enum.take(chronological, -n)
        _ -> chronological
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
  def last_entry(%__MODULE__{entries: [last | _]}), do: last

  @doc """
  Get the last assistant response content.
  """
  @spec last_assistant_content(t()) :: String.t() | nil
  def last_assistant_content(%__MODULE__{entries: entries}) do
    # Entries are stored in reverse order, so first match is most recent
    entries
    |> Enum.find(&(&1.role == :assistant))
    |> case do
      nil -> nil
      entry -> entry.content
    end
  end

  @doc """
  Returns a debug-friendly view of the thread contents.

  ## Options

  - `:last` - Number of entries to include (default: all)
  - `:truncate` - Max content length before truncation (default: 200)

  ## Example

      Thread.debug_view(thread, last: 5, truncate: 100)
      # %{
      #   id: "abc123",
      #   length: 12,
      #   system_prompt: "You are a weather...",
      #   entries: [...]
      # }
  """
  @spec debug_view(t(), keyword()) :: map()
  def debug_view(%__MODULE__{} = thread, opts \\ []) do
    last = Keyword.get(opts, :last)
    truncate = Keyword.get(opts, :truncate, 200)

    # Entries are stored in reverse order, so reverse to get chronological order
    chronological = Enum.reverse(thread.entries)

    entries =
      case last do
        nil -> chronological
        n when is_integer(n) and n > 0 -> Enum.take(chronological, -n)
        _ -> chronological
      end

    %{
      id: thread.id,
      length: Kernel.length(thread.entries),
      system_prompt: truncate_string(thread.system_prompt, truncate),
      entries: Enum.map(entries, &entry_to_debug_map(&1, truncate))
    }
  end

  @doc """
  Pretty-prints the thread to the console for IEx debugging.

  Prints each message with its role and content in a readable format.

  ## Example

      Thread.pp(thread)
      # [system] You are a weather assistant...
      # [user]   What's the weather in Seattle?
      # [asst]   <tool: get_weather>
      # [tool]   {"temp": 62, "conditions": "cloudy"}
      # [asst]   The weather is 62°F and cloudy.
  """
  @spec pp(t()) :: :ok
  def pp(%__MODULE__{} = thread) do
    if thread.system_prompt do
      IO.puts("[system] #{truncate_string(thread.system_prompt, 60)}")
    end

    # Entries are stored in reverse order, so reverse for display
    thread.entries
    |> Enum.reverse()
    |> Enum.each(fn entry ->
      IO.puts(format_entry_for_pp(entry))
    end)

    :ok
  end

  defp entry_to_debug_map(entry, truncate) do
    base = %{role: entry.role}

    base
    |> maybe_add(:content, truncate_string(entry.content, truncate))
    |> maybe_add(:tool_calls, format_tool_calls_for_debug(entry.tool_calls))
    |> maybe_add(:name, entry.name)
    |> maybe_add(:tool_call_id, entry.tool_call_id)
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  defp format_tool_calls_for_debug(nil), do: nil
  defp format_tool_calls_for_debug([]), do: nil

  defp format_tool_calls_for_debug(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      case tc do
        %{name: name} -> name
        %{"name" => name} -> name
        _ -> "unknown"
      end
    end)
  end

  defp truncate_string(nil, _max), do: nil
  defp truncate_string(str, max) when byte_size(str) <= max, do: str
  defp truncate_string(str, max), do: String.slice(str, 0, max) <> "..."

  defp format_entry_for_pp(%Entry{role: :user, content: content}) do
    "[user]   #{content}"
  end

  defp format_entry_for_pp(%Entry{role: :assistant, content: content, tool_calls: nil}) do
    "[asst]   #{content}"
  end

  defp format_entry_for_pp(%Entry{role: :assistant, tool_calls: tool_calls}) when is_list(tool_calls) do
    names =
      Enum.map_join(tool_calls, ", ", fn tc ->
        case tc do
          %{name: name} -> name
          %{"name" => name} -> name
          _ -> "?"
        end
      end)

    "[asst]   <tool: #{names}>"
  end

  defp format_entry_for_pp(%Entry{role: :tool, name: name, content: content}) do
    truncated = truncate_string(content, 60)
    "[tool]   #{name}: #{truncated}"
  end

  defp format_entry_for_pp(%Entry{role: :system, content: content}) do
    "[system] #{content}"
  end

  defp format_entry_for_pp(%Entry{role: role, content: content}) do
    "[#{role}] #{content}"
  end

  # Private helpers

  defp entry_to_message(%Entry{role: :user, content: content}) do
    %{role: :user, content: content}
  end

  defp entry_to_message(%Entry{role: :assistant, content: content, thinking: thinking, tool_calls: nil}) do
    %{role: :assistant, content: build_assistant_content(content, thinking)}
  end

  defp entry_to_message(%Entry{role: :assistant, content: content, thinking: thinking, tool_calls: tool_calls}) do
    %{role: :assistant, content: build_assistant_content(content || "", thinking), tool_calls: tool_calls}
  end

  defp entry_to_message(%Entry{role: :tool, tool_call_id: id, name: name, content: content}) do
    %{role: :tool, tool_call_id: id, name: name, content: content}
  end

  defp entry_to_message(%Entry{role: :system, content: content}) do
    %{role: :system, content: content}
  end

  defp build_assistant_content(content, nil), do: content
  defp build_assistant_content(content, ""), do: content

  defp build_assistant_content(content, thinking) when is_binary(thinking) do
    [
      %{type: :thinking, thinking: thinking},
      %{type: :text, text: content || ""}
    ]
  end

  defp message_to_entry(msg) when is_map(msg) do
    role = get_field(msg, :role, "role")
    content = get_field(msg, :content, "content")
    {text_content, thinking} = extract_entry_thinking(content)

    %Entry{
      role: normalize_role(role),
      content: text_content,
      thinking: thinking,
      tool_calls: get_field(msg, :tool_calls, "tool_calls"),
      tool_call_id: get_field(msg, :tool_call_id, "tool_call_id"),
      name: get_field(msg, :name, "name")
    }
  end

  defp extract_entry_thinking(content) when is_list(content) do
    thinking =
      content
      |> Enum.filter(fn
        %{type: :thinking} -> true
        %{type: "thinking"} -> true
        _ -> false
      end)
      |> Enum.map_join("", fn
        %{thinking: t} when is_binary(t) -> t
        %{text: t} when is_binary(t) -> t
        _ -> ""
      end)

    text =
      content
      |> Enum.filter(fn
        %{type: :text} -> true
        %{type: "text"} -> true
        _ -> false
      end)
      |> Enum.map_join("", fn
        %{text: t} when is_binary(t) -> t
        _ -> ""
      end)

    thinking = if thinking == "", do: nil, else: thinking
    {text, thinking}
  end

  defp extract_entry_thinking(content), do: {content, nil}

  # Helper to get a field from either atom or string key
  defp get_field(map, atom_key, string_key) do
    Map.get(map, atom_key) || Map.get(map, string_key)
  end

  # Known roles - normalize to atoms
  defp normalize_role(:user), do: :user
  defp normalize_role(:assistant), do: :assistant
  defp normalize_role(:tool), do: :tool
  defp normalize_role(:system), do: :system
  defp normalize_role("user"), do: :user
  defp normalize_role("assistant"), do: :assistant
  defp normalize_role("tool"), do: :tool
  defp normalize_role("system"), do: :system
  # OpenAI-specific roles
  defp normalize_role(:developer), do: :developer
  defp normalize_role("developer"), do: :developer
  defp normalize_role(:function), do: :function
  defp normalize_role("function"), do: :function
  # Pass through unknown roles as-is (atoms stay atoms, strings stay strings)
  defp normalize_role(role), do: role

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end

defimpl Inspect, for: Jido.AI.Thread do
  def inspect(thread, _opts) do
    len = Kernel.length(thread.entries)
    last_roles = thread.entries |> Enum.take(-2) |> Enum.map(& &1.role)

    suffix = if len > 0, do: ", last: #{Kernel.inspect(last_roles)}", else: ""
    "#Thread<#{len} entries#{suffix}>"
  end
end
