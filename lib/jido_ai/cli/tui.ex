defmodule Jido.AI.CLI.TUI do
  @moduledoc """
  Terminal UI for Jido AI agents using TermUI (Elm Architecture).

  Provides an interactive interface for querying agents with:
  - Text input for prompts
  - Real-time status display  
  - Scrollable output history
  - **Multi-turn conversation support** (agent persists across queries)
  - Session metrics (message count, token usage)

  ## Usage

      mix jido_ai.agent --tui
      mix jido_ai.agent --tui --type cot
      mix jido_ai.agent --tui --agent MyApp.WeatherAgent

  ## Multi-Turn Conversations

  The TUI now keeps the agent process alive between queries, enabling
  true multi-turn conversations. The agent maintains conversation history,
  so follow-up questions understand context from prior turns.

  Example session:
      You: What's the weather in Seattle?
      Agent: It's currently 52°F and cloudy...
      You: What about tomorrow?
      Agent: Tomorrow in Seattle expect...  (knows you mean Seattle!)

  Use Ctrl+R to reset the conversation and start fresh.
  """

  use TermUI.Elm

  alias Jido.AI.CLI.Adapter
  alias TermUI.Renderer.Style

  defstruct [
    :adapter,
    :agent_module,
    :config,
    :agent_pid,
    status: :idle,
    input: "",
    output: [],
    error: nil,
    start_time: nil,
    turn_count: 0,
    total_usage: %{input_tokens: 0, output_tokens: 0}
  ]

  @impl true
  def init(opts) do
    config = Keyword.get(opts, :config) || %{}
    adapter = config[:adapter]
    agent_module = config[:agent_module]

    %__MODULE__{
      adapter: adapter,
      agent_module: agent_module,
      config: config,
      agent_pid: nil,
      status: :idle,
      input: "",
      output: [],
      turn_count: 0,
      total_usage: %{input_tokens: 0, output_tokens: 0}
    }
  end

  @impl true
  def event_to_msg(event, state) do
    case event do
      %TermUI.Event.Key{key: :enter} when state.status == :idle and state.input != "" ->
        {:msg, {:submit, state.input}}

      %TermUI.Event.Key{key: :escape} ->
        {:msg, :quit}

      %TermUI.Event.Key{key: :ctrl_c} ->
        {:msg, :quit}

      # Ctrl+R: Reset conversation (restart agent)
      %TermUI.Event.Key{key: :ctrl_r} when state.status == :idle ->
        {:msg, :reset_conversation}

      %TermUI.Event.Key{char: char} when is_binary(char) and char != "" and state.status == :idle ->
        {:msg, {:char, char}}

      %TermUI.Event.Key{key: :backspace} when state.status == :idle ->
        {:msg, :backspace}

      %TermUI.Event.Key{key: :ctrl_u} when state.status == :idle ->
        {:msg, :clear_input}

      _ ->
        :ignore
    end
  end

  @impl true
  def update(msg, state) do
    case msg do
      {:char, char} ->
        {%{state | input: state.input <> char}, []}

      :backspace ->
        new_input = String.slice(state.input, 0, max(0, String.length(state.input) - 1))
        {%{state | input: new_input}, []}

      :clear_input ->
        {%{state | input: ""}, []}

      {:submit, query} ->
        # Ensure agent is started (lazy initialization)
        state = ensure_agent_started(state)

        case state.agent_pid do
          nil ->
            # Agent failed to start
            state = add_output(state, {:error, "Failed to start agent", 0})
            {%{state | status: :idle}, []}

          _pid ->
            state = %{state | status: :running, input: "", start_time: System.monotonic_time(:millisecond)}
            state = add_output(state, {:user, query})
            spawn_query(query, state)
            {state, []}
        end

      {:query_result, {:ok, result}} ->
        elapsed = System.monotonic_time(:millisecond) - (state.start_time || 0)
        state = add_output(state, {:assistant, result.answer, elapsed, result.meta})

        # Accumulate usage across turns
        usage = Map.get(result.meta, :usage, %{})

        new_total =
          Map.merge(state.total_usage, usage, fn _k, v1, v2 ->
            (v1 || 0) + (v2 || 0)
          end)

        {%{state | status: :idle, error: nil, turn_count: state.turn_count + 1, total_usage: new_total}, []}

      {:query_result, {:error, reason}} ->
        elapsed = System.monotonic_time(:millisecond) - (state.start_time || 0)
        error_msg = format_error(reason)
        state = add_output(state, {:error, error_msg, elapsed})
        {%{state | status: :idle, error: error_msg}, []}

      :reset_conversation ->
        # Stop current agent and reset state
        state = stop_agent(state)

        state = %{
          state
          | agent_pid: nil,
            output: [],
            turn_count: 0,
            total_usage: %{input_tokens: 0, output_tokens: 0},
            error: nil
        }

        state = add_output(state, {:system, "Conversation reset. Starting fresh."})
        {state, []}

      :quit ->
        # Clean up agent before quitting
        state = stop_agent(state)
        {state, [TermUI.Command.quit()]}

      _ ->
        {state, []}
    end
  end

  def handle_info({:query_result, result}, state) do
    update({:query_result, result}, state)
  end

  def handle_info(_msg, state) do
    {state, []}
  end

  @impl true
  def view(state) do
    style_header = Style.new() |> Style.fg(:cyan)
    style_status_idle = Style.new() |> Style.fg(:green)
    style_status_running = Style.new() |> Style.fg(:yellow)
    style_prompt = Style.new() |> Style.fg(:cyan) |> Style.bold()
    style_footer = Style.new() |> Style.fg(:black) |> Style.bg(:white)
    style_user = Style.new() |> Style.fg(:blue) |> Style.bold()
    style_assistant = Style.new() |> Style.fg(:green) |> Style.bold()
    style_error = Style.new() |> Style.fg(:red) |> Style.bold()
    style_system = Style.new() |> Style.fg(:magenta) |> Style.italic()

    status_text = if state.status == :idle, do: "Ready", else: "Thinking..."
    status_style = if state.status == :idle, do: style_status_idle, else: style_status_running

    agent_name =
      case state.agent_module do
        nil -> "ephemeral"
        mod -> inspect(mod) |> String.replace("Elixir.", "")
      end

    # Session metrics
    turns_text = "Turns: #{state.turn_count}"

    tokens_text =
      if state.total_usage.input_tokens > 0 or state.total_usage.output_tokens > 0 do
        total = state.total_usage.input_tokens + state.total_usage.output_tokens
        "│ Tokens: #{format_number(total)}"
      else
        ""
      end

    output_lines = render_output_lines(state.output, style_user, style_assistant, style_error, style_system)

    prompt_char = if state.status == :idle, do: "❯ ", else: "⏳ "
    input_text = if state.status == :idle, do: state.input <> "▌", else: "Processing..."

    box(
      [
        stack(:vertical, [
          # Header with session metrics
          text("Agent: #{agent_name} │ #{turns_text} #{tokens_text} │ Status: ", style_header),
          text(status_text, status_style),
          text(""),
          # Output area
          stack(:vertical, output_lines),
          text(""),
          # Input line
          stack(:horizontal, [
            text(prompt_char, style_prompt),
            text(input_text)
          ]),
          # Footer with multi-turn hint
          text(" Enter: Submit │ Ctrl+R: Reset │ Ctrl+U: Clear │ Esc: Quit ", style_footer)
        ])
      ],
      border: :rounded,
      title: " Jido AI Agent (Multi-Turn) "
    )
  end

  defp format_number(n) when n >= 1000, do: "#{Float.round(n / 1000, 1)}k"
  defp format_number(n), do: "#{n}"

  defp render_output_lines(output, style_user, style_assistant, style_error, style_system) do
    output
    |> Enum.reverse()
    |> Enum.flat_map(fn
      {:user, query} ->
        [
          text("You:", style_user),
          text("  #{query}")
        ]

      {:assistant, answer, elapsed_ms, meta} ->
        # Show per-turn metrics if available
        iterations = Map.get(meta, :iterations, 0)
        usage = Map.get(meta, :usage, %{})
        tokens = Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0)

        metrics =
          [
            "#{elapsed_ms}ms",
            if(iterations > 0, do: "#{iterations} iter"),
            if(tokens > 0, do: "#{format_number(tokens)} tok")
          ]
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        [
          text("Agent (#{metrics}):", style_assistant),
          text("  #{String.slice(answer || "", 0, 500)}")
        ]

      {:assistant, answer, elapsed_ms} ->
        # Backward compat: no meta
        [
          text("Agent (#{elapsed_ms}ms):", style_assistant),
          text("  #{String.slice(answer || "", 0, 500)}")
        ]

      {:error, error, elapsed_ms} ->
        [
          text("Error (#{elapsed_ms}ms):", style_error),
          text("  #{error}")
        ]

      {:system, message} ->
        [
          text("System:", style_system),
          text("  #{message}")
        ]
    end)
  end

  defp add_output(state, entry) do
    %{state | output: [entry | state.output]}
  end

  defp ensure_agent_started(%{agent_pid: pid} = state) when is_pid(pid) do
    # Check if agent is still alive
    if Process.alive?(pid) do
      state
    else
      # Agent died, restart it
      start_new_agent(state)
    end
  end

  defp ensure_agent_started(state), do: start_new_agent(state)

  defp start_new_agent(state) do
    adapter = state.adapter
    agent_module = state.agent_module

    case adapter.start_agent(JidoAi.CliJido, agent_module, state.config) do
      {:ok, pid} ->
        %{state | agent_pid: pid}

      {:error, reason} ->
        state = add_output(state, {:error, "Failed to start agent: #{inspect(reason)}", 0})
        %{state | agent_pid: nil}
    end
  end

  defp stop_agent(%{agent_pid: nil} = state), do: state

  defp stop_agent(%{agent_pid: pid, adapter: adapter} = state) when is_pid(pid) do
    try do
      adapter.stop(pid)
    catch
      :exit, _ -> :ok
    end

    %{state | agent_pid: nil}
  end

  defp spawn_query(query, state) do
    pid = state.agent_pid
    agent_module = state.agent_module
    config = state.config
    caller = self()

    spawn(fn ->
      result = run_query_on_agent(query, pid, agent_module, config)
      send(caller, {:query_result, result})
    end)
  end

  defp run_query_on_agent(query, pid, agent_module, config) do
    # Submit query to the persistent agent (multi-turn enabled!)
    case agent_module.ask(pid, query) do
      {:ok, request} ->
        case agent_module.await(request, timeout: config.timeout) do
          {:ok, answer} ->
            # Get agent status for metadata
            meta = get_agent_meta(pid)
            {:ok, %{answer: answer, meta: meta}}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_agent_meta(pid) do
    case Jido.AgentServer.status(pid) do
      {:ok, status} ->
        strategy_state = Map.get(status.raw_state, :__strategy__, %{})
        details = Map.get(status.snapshot, :details, %{})

        %{
          iterations: Map.get(strategy_state, :iteration, 0),
          usage: extract_usage(strategy_state, details),
          model: Map.get(details, :model)
        }

      _ ->
        %{}
    end
  end

  defp extract_usage(strategy_state, details) do
    usage = Map.get(strategy_state, :usage) || Map.get(details, :usage) || %{}

    if map_size(usage) > 0 do
      %{
        input_tokens: Map.get(usage, :input_tokens, 0),
        output_tokens: Map.get(usage, :output_tokens, 0)
      }
    else
      %{input_tokens: 0, output_tokens: 0}
    end
  end

  defp format_error(:timeout), do: "Timeout waiting for agent completion"
  defp format_error(:not_found), do: "Agent process not found"
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  @doc """
  Start the TUI with the given configuration.
  """
  def run(config) do
    case Adapter.resolve(config.type, config.user_agent_module) do
      {:ok, adapter} ->
        agent_module = config.user_agent_module || adapter.create_ephemeral_agent(config)
        config = Map.merge(config, %{adapter: adapter, agent_module: agent_module})

        TermUI.Runtime.run(root: __MODULE__, config: config)

      {:error, reason} ->
        IO.puts(:stderr, "Error: #{reason}")
        System.halt(1)
    end
  end
end
