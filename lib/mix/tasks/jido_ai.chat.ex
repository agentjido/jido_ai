defmodule Mix.Tasks.JidoAi.Chat do
  @shortdoc "Start an interactive chat session with a Jido AI agent"

  @moduledoc """
  Start an interactive terminal chat with a Jido AI agent.

  Provides a multi-turn conversation interface where the agent maintains
  context across messages. Uses term_ui for a rich terminal experience.

  ## Quick Start

      # Start chat with default ReAct agent
      mix jido_ai.chat

      # Chat with specific model
      mix jido_ai.chat --model anthropic:claude-sonnet-4-20250514

      # Chat with a custom agent
      mix jido_ai.chat --agent MyApp.WeatherAgent

  ## Options

  ### Agent Configuration
      --agent MODULE       Use existing agent module
      --type TYPE          Agent type: react (default), cot, tot, got, trm, adaptive
      --model MODEL        LLM model (default: anthropic:claude-haiku-4-5)
      --tools MODULES      Comma-separated tool modules
      --system PROMPT      System prompt
      --max-iterations N   Max reasoning iterations (default: 10)

  ### Execution
      --timeout MS         Timeout per message in ms (default: 60000)

  ## Keyboard Controls

  - **Enter** - Send message
  - **Backspace** - Delete character
  - **Esc** or **Ctrl+C** - Quit

  ## Examples

      # Default chat
      mix jido_ai.chat

      # Use GPT-4
      mix jido_ai.chat --model openai:gpt-4o

      # Use Chain-of-Thought reasoning
      mix jido_ai.chat --type cot

      # Custom agent with weather tools
      mix jido_ai.chat --agent MyApp.WeatherAgent

  ## See Also

  - `mix help jido_ai.agent` - Single-shot queries
  """

  use Mix.Task

  alias Jido.AI.CLI.TUI

  require Logger

  @impl Mix.Task
  def run(argv) do
    Mix.Task.rerun("app.start")
    load_dotenv()
    start_jido_instance()

    {opts, _args, _invalid} =
      OptionParser.parse(argv,
        strict: [
          type: :string,
          agent: :string,
          model: :string,
          tools: :string,
          system: :string,
          max_iterations: :integer,
          timeout: :integer
        ],
        aliases: [
          t: :type,
          a: :agent,
          m: :model,
          s: :system
        ]
      )

    config = build_config(opts)

    case TUI.run(config) do
      :ok -> :ok
      {:error, _reason} -> System.halt(1)
    end
  end

  defp build_config(opts) do
    %{
      type: opts[:type],
      user_agent_module: parse_module(opts[:agent]),
      model: opts[:model],
      tools: parse_tools(opts[:tools]),
      system_prompt: opts[:system],
      max_iterations: opts[:max_iterations],
      timeout: opts[:timeout] || 60_000
    }
  end

  defp parse_module(nil), do: nil

  defp parse_module(module_string) do
    module = Module.concat([module_string])

    if Code.ensure_loaded?(module) do
      module
    else
      raise "Module #{module_string} not found or not loaded"
    end
  end

  defp parse_tools(nil), do: nil

  defp parse_tools(tools_string) do
    tools_string
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn mod_string ->
      module = Module.concat([mod_string])

      if !Code.ensure_loaded?(module) do
        raise "Tool module #{mod_string} not found"
      end

      module
    end)
  end

  defp start_jido_instance do
    case Process.whereis(JidoAi.TuiJido) do
      nil ->
        {:ok, _pid} = Jido.start_link(name: JidoAi.TuiJido)
        :ok

      _pid ->
        :ok
    end
  end

  defp load_dotenv do
    if Code.ensure_loaded?(Dotenvy) do
      env_file = Path.join(File.cwd!(), ".env")

      if File.exists?(env_file) do
        Dotenvy.source!([env_file])
      end
    end
  end
end
