defmodule Jido.AI.Thread do
  @moduledoc """
  Deprecated compatibility shim for the legacy ReAct thread API.

  `Jido.AI.Thread` is deprecated. Use `Jido.AI.Context` for all new code.
  This module keeps backwards compatibility and delegates behavior to
  `Jido.AI.Context`.
  """

  require Logger

  alias Jido.AI.Context
  alias __MODULE__.Entry

  @warning_prefix "DEPRECATION: Jido.AI.Thread is deprecated; use Jido.AI.Context"

  @type t :: %__MODULE__{
          id: String.t(),
          entries: [Entry.t()],
          system_prompt: String.t() | nil
        }

  defstruct [:id, entries: [], system_prompt: nil]

  defmodule Entry do
    @moduledoc false

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

  @doc "Deprecated shim for `Jido.AI.Context.new/1`."
  @deprecated "Use Jido.AI.Context.new/1"
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    warn_deprecated("new/1")

    opts
    |> Context.new()
    |> from_context()
  end

  @doc "Deprecated shim for `Jido.AI.Context.append/2`."
  @deprecated "Use Jido.AI.Context.append/2"
  @spec append(t(), Entry.t()) :: t()
  def append(%__MODULE__{} = thread, entry) do
    warn_deprecated("append/2")

    thread
    |> to_context()
    |> Context.append(entry_to_context_entry(entry))
    |> from_context()
  end

  @doc "Deprecated shim for `Jido.AI.Context.append_user/2`."
  @deprecated "Use Jido.AI.Context.append_user/2"
  @spec append_user(t(), String.t()) :: t()
  def append_user(%__MODULE__{} = thread, content) when is_binary(content) do
    warn_deprecated("append_user/2")

    thread
    |> to_context()
    |> Context.append_user(content)
    |> from_context()
  end

  @doc "Deprecated shim for `Jido.AI.Context.append_assistant/4`."
  @deprecated "Use Jido.AI.Context.append_assistant/4"
  @spec append_assistant(t(), String.t() | nil, list() | nil, keyword()) :: t()
  def append_assistant(%__MODULE__{} = thread, content, tool_calls \\ nil, opts \\ []) do
    warn_deprecated("append_assistant/4")

    thread
    |> to_context()
    |> Context.append_assistant(content, tool_calls, opts)
    |> from_context()
  end

  @doc "Deprecated shim for `Jido.AI.Context.append_tool_result/4`."
  @deprecated "Use Jido.AI.Context.append_tool_result/4"
  @spec append_tool_result(t(), String.t(), String.t(), String.t()) :: t()
  def append_tool_result(%__MODULE__{} = thread, tool_call_id, name, content) do
    warn_deprecated("append_tool_result/4")

    thread
    |> to_context()
    |> Context.append_tool_result(tool_call_id, name, content)
    |> from_context()
  end

  @doc "Deprecated shim for `Jido.AI.Context.to_messages/2`."
  @deprecated "Use Jido.AI.Context.to_messages/2"
  @spec to_messages(t(), keyword()) :: [map()]
  def to_messages(%__MODULE__{} = thread, opts \\ []) do
    warn_deprecated("to_messages/2")

    thread
    |> to_context()
    |> Context.to_messages(opts)
  end

  @doc "Deprecated shim for `Jido.AI.Context.append_messages/2`."
  @deprecated "Use Jido.AI.Context.append_messages/2"
  @spec append_messages(t(), [map()]) :: t()
  def append_messages(%__MODULE__{} = thread, messages) when is_list(messages) do
    warn_deprecated("append_messages/2")

    thread
    |> to_context()
    |> Context.append_messages(messages)
    |> from_context()
  end

  @doc "Deprecated shim for `Jido.AI.Context.length/1`."
  @deprecated "Use Jido.AI.Context.length/1"
  @spec length(t()) :: non_neg_integer()
  def length(%__MODULE__{} = thread) do
    warn_deprecated("length/1")

    thread
    |> to_context()
    |> Context.length()
  end

  @doc "Deprecated shim for `Jido.AI.Context.empty?/1`."
  @deprecated "Use Jido.AI.Context.empty?/1"
  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{} = thread) do
    warn_deprecated("empty?/1")

    thread
    |> to_context()
    |> Context.empty?()
  end

  @doc "Deprecated shim for `Jido.AI.Context.clear/1`."
  @deprecated "Use Jido.AI.Context.clear/1"
  @spec clear(t()) :: t()
  def clear(%__MODULE__{} = thread) do
    warn_deprecated("clear/1")

    thread
    |> to_context()
    |> Context.clear()
    |> from_context()
  end

  @doc "Deprecated shim for `Jido.AI.Context.last_entry/1`."
  @deprecated "Use Jido.AI.Context.last_entry/1"
  @spec last_entry(t()) :: Entry.t() | nil
  def last_entry(%__MODULE__{} = thread) do
    warn_deprecated("last_entry/1")

    thread
    |> to_context()
    |> Context.last_entry()
    |> context_entry_to_thread_entry()
  end

  @doc "Deprecated shim for `Jido.AI.Context.last_assistant_content/1`."
  @deprecated "Use Jido.AI.Context.last_assistant_content/1"
  @spec last_assistant_content(t()) :: String.t() | nil
  def last_assistant_content(%__MODULE__{} = thread) do
    warn_deprecated("last_assistant_content/1")

    thread
    |> to_context()
    |> Context.last_assistant_content()
  end

  @doc "Deprecated shim for `Jido.AI.Context.debug_view/2`."
  @deprecated "Use Jido.AI.Context.debug_view/2"
  @spec debug_view(t(), keyword()) :: map()
  def debug_view(%__MODULE__{} = thread, opts \\ []) do
    warn_deprecated("debug_view/2")

    thread
    |> to_context()
    |> Context.debug_view(opts)
  end

  @doc "Deprecated shim for `Jido.AI.Context.pp/1`."
  @deprecated "Use Jido.AI.Context.pp/1"
  @spec pp(t()) :: :ok
  def pp(%__MODULE__{} = thread) do
    warn_deprecated("pp/1")

    thread
    |> to_context()
    |> Context.pp()
  end

  @doc "Deprecated conversion helper. Converts a legacy thread to `Jido.AI.Context`."
  @spec to_context(t()) :: Context.t()
  def to_context(%__MODULE__{} = thread) do
    %Context{
      id: thread.id,
      system_prompt: thread.system_prompt,
      entries: Enum.map(thread.entries, &entry_to_context_entry/1)
    }
  end

  @doc "Deprecated conversion helper. Converts `Jido.AI.Context` to a legacy thread."
  @spec from_context(Context.t()) :: t()
  def from_context(%Context{} = context) do
    %__MODULE__{
      id: context.id,
      system_prompt: context.system_prompt,
      entries: Enum.map(context.entries, &context_entry_to_thread_entry/1)
    }
  end

  defp entry_to_context_entry(%Context.Entry{} = entry), do: entry

  defp entry_to_context_entry(%Entry{} = entry) do
    %Context.Entry{
      role: entry.role,
      content: entry.content,
      thinking: entry.thinking,
      tool_calls: entry.tool_calls,
      tool_call_id: entry.tool_call_id,
      name: entry.name,
      timestamp: entry.timestamp
    }
  end

  defp entry_to_context_entry(%{} = entry) do
    %Context.Entry{
      role: get_field(entry, :role),
      content: get_field(entry, :content),
      thinking: get_field(entry, :thinking),
      tool_calls: get_field(entry, :tool_calls),
      tool_call_id: get_field(entry, :tool_call_id),
      name: get_field(entry, :name),
      timestamp: get_field(entry, :timestamp)
    }
  end

  defp context_entry_to_thread_entry(nil), do: nil
  defp context_entry_to_thread_entry(%Entry{} = entry), do: entry

  defp context_entry_to_thread_entry(%Context.Entry{} = entry) do
    %Entry{
      role: entry.role,
      content: entry.content,
      thinking: entry.thinking,
      tool_calls: entry.tool_calls,
      tool_call_id: entry.tool_call_id,
      name: entry.name,
      timestamp: entry.timestamp
    }
  end

  defp context_entry_to_thread_entry(%{} = entry) do
    %Entry{
      role: get_field(entry, :role),
      content: get_field(entry, :content),
      thinking: get_field(entry, :thinking),
      tool_calls: get_field(entry, :tool_calls),
      tool_call_id: get_field(entry, :tool_call_id),
      name: get_field(entry, :name),
      timestamp: get_field(entry, :timestamp)
    }
  end

  defp warn_deprecated(function_name) do
    Logger.warning("#{@warning_prefix}. Called #{function_name}.")
  end

  defp get_field(map, key) do
    Map.get(map, key, Map.get(map, Atom.to_string(key)))
  end
end

defimpl Inspect, for: Jido.AI.Thread do
  def inspect(thread, _opts) do
    case thread.entries do
      entries when is_list(entries) ->
        len = Kernel.length(entries)
        last_roles = entries |> Enum.reverse() |> Enum.take(-2) |> Enum.map(&entry_role/1)
        suffix = if len > 0, do: ", last: #{Kernel.inspect(last_roles)}", else: ""
        "#Thread<#{len} entries#{suffix}>"

      %{type: :list, size: size} when is_integer(size) and size >= 0 ->
        "#Thread<#{size} entries, truncated>"

      _ ->
        "#Thread<unknown entries>"
    end
  end

  defp entry_role(%{role: role}), do: role
  defp entry_role(%{"role" => role}), do: role
  defp entry_role(_), do: :unknown
end
