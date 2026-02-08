defmodule Jido.AI.CLI.TUI do
  @moduledoc """
  Terminal UI for multi-turn conversations with Jido AI agents.

  Uses term_ui to provide an interactive chat interface with:
  - Message history display
  - Text input
  - Status display showing model, tokens, and elapsed time
  - Support for multiple agent types (ReAct, CoT, ToT, etc.)

  ## Usage

      Jido.AI.CLI.TUI.run(config)

  Where config contains adapter, agent_module, timeout, and other settings
  from the mix task.
  """

  use TermUI.Elm

  alias Jido.AI.CLI.Adapter
  alias TermUI.Command
  alias TermUI.Style

  require Logger

  @doc """
  Starts the TUI with the given configuration.
  """
  @spec run(map()) :: :ok | {:error, term()}
  def run(config) when is_map(config) do
    case resolve_adapter_and_agent(config) do
      {:ok, adapter, agent_module} ->
        config = Map.merge(config, %{adapter: adapter, agent_module: agent_module})
        TermUI.Runtime.run(root: __MODULE__, opts: config)

      {:error, reason} ->
        IO.puts(:stderr, "Fatal: #{format_error(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :opts, %{})

    %{
      adapter: config[:adapter],
      agent_module: config[:agent_module],
      agent_pid: nil,
      pending_query_ref: nil,
      timeout: config[:timeout] || 60_000,
      config: config,
      input_buffer: "",
      messages: [],
      status: :ready,
      error: nil,
      last_meta: nil
    }
  end

  @impl true
  def event_to_msg(%TermUI.Event.Key{key: :escape}, _state) do
    {:msg, :quit}
  end

  def event_to_msg(%TermUI.Event.Key{char: "c", modifiers: [:ctrl]}, _state) do
    {:msg, :quit}
  end

  def event_to_msg(%TermUI.Event.Key{key: :enter}, state) do
    if String.trim(state.input_buffer) != "" and state.status == :ready do
      {:msg, {:submit, state.input_buffer}}
    else
      :ignore
    end
  end

  def event_to_msg(%TermUI.Event.Key{key: :backspace}, _state) do
    {:msg, :backspace}
  end

  def event_to_msg(%TermUI.Event.Key{char: char}, _state) when is_binary(char) do
    {:msg, {:char, char}}
  end

  def event_to_msg(_event, _state) do
    :ignore
  end

  @impl true
  def update(:quit, state) do
    cleanup_agent(state)
    {state, [Command.quit()]}
  end

  def update(:backspace, state) do
    new_buffer =
      if String.length(state.input_buffer) > 0 do
        String.slice(state.input_buffer, 0..-2//1)
      else
        ""
      end

    {%{state | input_buffer: new_buffer}, []}
  end

  def update({:char, char}, state) do
    if state.status == :ready do
      {%{state | input_buffer: state.input_buffer <> char}, []}
    else
      {state, []}
    end
  end

  def update({:submit, query}, state) do
    user_msg = %{role: :user, content: query, timestamp: DateTime.utc_now()}
    messages = state.messages ++ [user_msg]

    new_state = %{
      state
      | messages: messages,
        input_buffer: "",
        status: :thinking,
        error: nil
    }

    {new_state, [Command.timer(1, {:do_query, query})]}
  end

  def update({:do_query, query}, state) do
    case ensure_agent_started(state) do
      {:ok, pid, new_state} ->
        query_ref = make_ref()
        started_at_ms = System.monotonic_time(:millisecond)
        owner = self()

        Task.start(fn ->
          result = execute_query(pid, query, new_state)
          send(owner, {:tui_query_result, query_ref, started_at_ms, result})
        end)

        {%{new_state | pending_query_ref: query_ref, status: :thinking}, []}

      {:error, reason} ->
        {%{state | status: :error, error: format_error(reason)}, []}
    end
  end

  def update({:tui_query_result, query_ref, started_at_ms, {:ok, result}}, state) do
    if state.pending_query_ref == query_ref do
      elapsed = System.monotonic_time(:millisecond) - started_at_ms

      assistant_msg = %{
        role: :assistant,
        content: result.answer,
        timestamp: DateTime.utc_now(),
        meta: Map.put(result.meta, :elapsed_ms, elapsed)
      }

      messages = state.messages ++ [assistant_msg]

      {%{state | messages: messages, status: :ready, last_meta: result.meta, pending_query_ref: nil}, []}
    else
      {state, []}
    end
  end

  def update({:tui_query_result, query_ref, _started_at_ms, {:error, reason}}, state) do
    if state.pending_query_ref == query_ref do
      {%{state | status: :error, error: format_error(reason), pending_query_ref: nil}, []}
    else
      {state, []}
    end
  end

  def update(_msg, state) do
    {state, []}
  end

  @impl true
  def view(state) do
    header = render_header()
    separator = text("─────────────────────────────────────────────────")
    messages_area = render_messages(state.messages)
    input_area = render_input(state)
    status_bar = render_status_bar(state)

    stack(:vertical, [
      header,
      separator,
      text(""),
      messages_area,
      text(""),
      separator,
      input_area,
      text(""),
      status_bar
    ])
  end

  defp render_header do
    title_style = Style.new() |> Style.fg(:cyan) |> Style.bold()
    help_style = Style.new() |> Style.fg(:white) |> Style.dim()

    stack(:horizontal, [
      text("Jido AI Chat", title_style),
      text("   "),
      text("(Esc to quit)", help_style)
    ])
  end

  defp render_messages(messages) do
    if Enum.empty?(messages) do
      empty_style = Style.new() |> Style.fg(:white) |> Style.dim()
      text("No messages yet. Type your question below.", empty_style)
    else
      visible_messages = Enum.take(messages, -10)

      rendered =
        Enum.flat_map(visible_messages, fn msg ->
          render_message(msg)
        end)

      stack(:vertical, rendered)
    end
  end

  defp render_message(msg) do
    {role_label, role_style} =
      case msg.role do
        :user ->
          {"You", Style.new() |> Style.fg(:green) |> Style.bold()}

        :assistant ->
          {"Assistant", Style.new() |> Style.fg(:cyan) |> Style.bold()}

        _ ->
          {"System", Style.new() |> Style.fg(:yellow) |> Style.bold()}
      end

    header = text("#{role_label}:", role_style)

    content_lines =
      msg.content
      |> String.split("\n")
      |> Enum.map(fn line -> text("  #{line}") end)

    meta_line =
      if msg[:meta] do
        meta_text = format_meta_inline(msg.meta)

        if meta_text == "" do
          []
        else
          meta_style = Style.new() |> Style.fg(:white) |> Style.dim()
          [text("  #{meta_text}", meta_style)]
        end
      else
        []
      end

    [header | content_lines] ++ meta_line ++ [text("")]
  end

  defp format_meta_inline(meta) do
    parts = []

    parts =
      if meta[:elapsed_ms] do
        parts ++ ["#{meta.elapsed_ms}ms"]
      else
        parts
      end

    parts =
      if meta[:iterations] && meta[:iterations] > 0 do
        parts ++ ["#{meta.iterations} iters"]
      else
        parts
      end

    parts =
      case meta[:usage] do
        %{input_tokens: input, output_tokens: output} when input > 0 or output > 0 ->
          total = input + output
          parts ++ ["#{format_tokens(total)} tokens"]

        _ ->
          parts
      end

    if Enum.empty?(parts), do: "", else: "(#{Enum.join(parts, " • ")})"
  end

  defp format_tokens(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_tokens(n), do: "#{n}"

  defp render_input(state) do
    {prompt, prompt_style} =
      case state.status do
        :thinking ->
          {"⏳ Thinking...", Style.new() |> Style.fg(:yellow)}

        :error ->
          {"❌ Error", Style.new() |> Style.fg(:red)}

        _ ->
          {"> ", Style.new() |> Style.fg(:green)}
      end

    input_style = Style.new() |> Style.fg(:white)

    cursor =
      if state.status == :ready do
        "█"
      else
        ""
      end

    stack(:horizontal, [
      text(prompt, prompt_style),
      text(state.input_buffer <> cursor, input_style)
    ])
  end

  defp render_status_bar(state) do
    style = Style.new() |> Style.fg(:white) |> Style.dim()

    left =
      case state.status do
        :ready -> "Ready"
        :thinking -> "Processing..."
        :error -> "Error: #{state.error}"
      end

    right =
      if state.last_meta && state.last_meta[:model] do
        "Model: #{state.last_meta.model}"
      else
        ""
      end

    stack(:horizontal, [
      text(left, style),
      text("   "),
      text(right, style)
    ])
  end

  defp ensure_agent_started(%{agent_pid: nil} = state) do
    adapter = state.adapter
    agent_module = state.agent_module

    case adapter.start_agent(JidoAi.TuiJido, agent_module, state.config) do
      {:ok, pid} ->
        {:ok, pid, %{state | agent_pid: pid}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_agent_started(%{agent_pid: pid} = state) when is_pid(pid) do
    case Jido.AgentServer.status(pid) do
      {:ok, _status} ->
        {:ok, pid, state}

      {:error, _reason} ->
        adapter = state.adapter
        agent_module = state.agent_module

        case adapter.start_agent(JidoAi.TuiJido, agent_module, state.config) do
          {:ok, new_pid} ->
            {:ok, new_pid, %{state | agent_pid: new_pid}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp execute_query(pid, query, state) do
    adapter = state.adapter
    config = Map.put(state.config, :agent_module, state.agent_module)

    case adapter.submit(pid, query, config) do
      {:ok, _request} ->
        adapter.await(pid, state.timeout, config)

      :ok ->
        adapter.await(pid, state.timeout, config)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp cleanup_agent(%{agent_pid: nil}), do: :ok

  defp cleanup_agent(%{agent_pid: pid, adapter: adapter}) when is_pid(pid) do
    adapter.stop(pid)
  end

  defp resolve_adapter_and_agent(config) do
    case Adapter.resolve(config[:type], config[:user_agent_module]) do
      {:ok, adapter} ->
        agent_module = config[:user_agent_module] || adapter.create_ephemeral_agent(config)
        {:ok, adapter, agent_module}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp format_error(:timeout), do: "Timeout waiting for agent"
  defp format_error(:not_found), do: "Agent not found"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)
end
