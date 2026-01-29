defmodule Jido.AI.CLI.TUI do
  @moduledoc """
  Terminal UI for Jido AI agents using TermUI (Elm Architecture).

  Provides an interactive interface for querying agents with:
  - Text input for prompts
  - Real-time status display  
  - Scrollable output history
  - Support for multiple queries in a session

  ## Usage

      mix jido_ai.agent --tui
      mix jido_ai.agent --tui --type cot
      mix jido_ai.agent --tui --agent MyApp.WeatherAgent
  """

  use TermUI.Elm

  alias Jido.AI.CLI.Adapter
  alias TermUI.Renderer.Style

  defstruct [
    :adapter,
    :agent_module,
    :config,
    status: :idle,
    input: "",
    output: [],
    error: nil,
    start_time: nil
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
      status: :idle,
      input: "",
      output: []
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
        state = %{state | status: :running, input: "", start_time: System.monotonic_time(:millisecond)}
        state = add_output(state, {:user, query})
        spawn_query(query, state)
        {state, []}

      {:query_result, {:ok, result}} ->
        elapsed = System.monotonic_time(:millisecond) - (state.start_time || 0)
        state = add_output(state, {:assistant, result.answer, elapsed})
        {%{state | status: :idle, error: nil}, []}

      {:query_result, {:error, reason}} ->
        elapsed = System.monotonic_time(:millisecond) - (state.start_time || 0)
        error_msg = format_error(reason)
        state = add_output(state, {:error, error_msg, elapsed})
        {%{state | status: :idle, error: error_msg}, []}

      :quit ->
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

    status_text = if state.status == :idle, do: "Ready", else: "Thinking..."
    status_style = if state.status == :idle, do: style_status_idle, else: style_status_running

    agent_name =
      case state.agent_module do
        nil -> "ephemeral"
        mod -> inspect(mod) |> String.replace("Elixir.", "")
      end

    output_lines = render_output_lines(state.output, style_user, style_assistant, style_error)

    prompt_char = if state.status == :idle, do: "❯ ", else: "⏳ "
    input_text = if state.status == :idle, do: state.input <> "▌", else: "Processing..."

    box(
      [
        stack(:vertical, [
          # Header
          text("Agent: #{agent_name} │ Status: ", style_header),
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
          # Footer
          text(" Enter: Submit │ Ctrl+U: Clear │ Esc: Quit ", style_footer)
        ])
      ],
      border: :rounded,
      title: " Jido AI Agent "
    )
  end

  defp render_output_lines(output, style_user, style_assistant, style_error) do
    output
    |> Enum.reverse()
    |> Enum.flat_map(fn
      {:user, query} ->
        [
          text("You:", style_user),
          text("  #{query}")
        ]

      {:assistant, answer, elapsed_ms} ->
        [
          text("Agent (#{elapsed_ms}ms):", style_assistant),
          text("  #{String.slice(answer, 0, 500)}")
        ]

      {:error, error, elapsed_ms} ->
        [
          text("Error (#{elapsed_ms}ms):", style_error),
          text("  #{error}")
        ]
    end)
  end

  defp add_output(state, entry) do
    %{state | output: [entry | state.output]}
  end

  defp spawn_query(query, state) do
    adapter = state.adapter
    agent_module = state.agent_module
    config = state.config
    caller = self()

    spawn(fn ->
      result = run_query(query, adapter, agent_module, config)
      send(caller, {:query_result, result})
    end)
  end

  defp run_query(query, adapter, agent_module, config) do
    case adapter.start_agent(JidoAi.CliJido, agent_module, config) do
      {:ok, pid} ->
        try do
          :ok = adapter.submit(pid, query, config)
          adapter.await(pid, config.timeout, config)
        after
          adapter.stop(pid)
        end

      {:error, reason} ->
        {:error, reason}
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
