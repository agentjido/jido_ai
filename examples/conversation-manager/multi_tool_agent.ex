defmodule Examples.ConversationManager.MultiToolAgent do
  @moduledoc """
  Advanced conversation agent with multiple tools and sophisticated state management.

  Demonstrates:
  - Multiple tool integration (Weather, Calculator, Search)
  - Error handling and recovery
  - Conversation metadata tracking
  - History analysis and statistics
  - Streaming responses with tools

  ## Usage

      # Run the full example
      Examples.ConversationManager.MultiToolAgent.run()

      # Create a custom agent
      {:ok, agent} = Examples.ConversationManager.MultiToolAgent.create_agent(%{
        tools: [WeatherAction, CalculatorAction],
        model: {:openai, [model: "gpt-4"]}
      })

      # Process messages with the agent
      {:ok, response, agent} = Examples.ConversationManager.MultiToolAgent.process(
        agent,
        "What's 15 * 23?"
      )

      # Analyze agent conversation
      {:ok, stats} = Examples.ConversationManager.MultiToolAgent.get_statistics(agent)

      # Cleanup
      :ok = Examples.ConversationManager.MultiToolAgent.destroy_agent(agent)
  """

  alias Jido.AI.Conversation.Manager, as: ConversationManager
  alias Jido.AI.Tools.Manager, as: ToolsManager
  alias Jido.AI.Model
  require Logger

  @default_options %{
    temperature: 0.7,
    max_tokens: 1500
  }

  @default_tools [
    Examples.ConversationManager.MockWeatherAction,
    Examples.ConversationManager.MockCalculatorAction,
    Examples.ConversationManager.MockSearchAction
  ]

  @type agent :: %{
          conversation_id: String.t(),
          tools: [module()],
          options: map(),
          created_at: DateTime.t(),
          message_count: non_neg_integer()
        }

  @doc """
  Runs the advanced multi-tool agent example.
  """
  def run do
    IO.puts("\n" <> String.duplicate("=", 70))
    IO.puts("  Conversation Manager: Multi-Tool Agent")
    IO.puts(String.duplicate("=", 70) <> "\n")

    IO.puts("Advanced agent with multiple tools and error handling")
    IO.puts("Features: Weather, Calculator, Search with retry logic\n")
    IO.puts(String.duplicate("-", 70) <> "\n")

    # Create agent with multiple tools
    tools = @default_tools

    options = %{
      temperature: 0.7,
      max_iterations: 10
    }

    IO.puts("Creating agent with #{length(tools)} tools...")

    case create_agent(%{tools: tools, options: options}) do
      {:ok, agent} ->
        display_agent_info(agent)

        # Run conversation scenarios
        agent = run_scenarios(agent)

        # Display final statistics
        display_final_statistics(agent)

        # Cleanup
        destroy_agent(agent)
        IO.puts("\nAgent destroyed successfully")

      {:error, reason} ->
        IO.puts("Error: Failed to create agent: #{inspect(reason)}")
    end

    IO.puts("\n" <> String.duplicate("=", 70))
  end

  @doc """
  Creates a new multi-tool agent.
  """
  @spec create_agent(map()) :: {:ok, agent()} | {:error, term()}
  def create_agent(config) do
    tools = Map.get(config, :tools, @default_tools)
    user_options = Map.get(config, :options, %{})
    model_spec = Map.get(config, :model, {:openai, [model: "gpt-4"]})

    options = Map.merge(@default_options, user_options)

    case Model.from(model_spec) do
      {:ok, model} ->
        case ConversationManager.create(model,
               system_prompt: "You are a helpful assistant with access to weather, calculator, and search tools.",
               options: options
             ) do
          {:ok, conversation_id} ->
            agent = %{
              conversation_id: conversation_id,
              tools: tools,
              options: options,
              created_at: DateTime.utc_now(),
              message_count: 0
            }

            {:ok, agent}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, {:model_error, reason}}
    end
  end

  @doc """
  Processes a message with the agent, including error handling and retry logic.
  """
  @spec process(agent(), String.t(), keyword()) :: {:ok, map(), agent()} | {:error, term()}
  def process(agent, message, opts \\ []) do
    retries = Keyword.get(opts, :retries, 2)
    log_enabled = Keyword.get(opts, :log, true)

    if log_enabled do
      Logger.info("Processing message",
        conversation_id: agent.conversation_id,
        message_length: String.length(message)
      )
    end

    case process_with_retry(agent, message, retries) do
      {:ok, response} ->
        updated_agent = %{agent | message_count: agent.message_count + 1}

        if log_enabled do
          Logger.info("Message processed successfully",
            conversation_id: agent.conversation_id,
            tool_calls: Map.get(response, :tool_calls_made, 0)
          )
        end

        {:ok, response, updated_agent}

      {:error, reason} = error ->
        if log_enabled do
          Logger.error("Message processing failed",
            conversation_id: agent.conversation_id,
            error: inspect(reason)
          )
        end

        error
    end
  end

  @doc """
  Processes a message with streaming support.
  """
  @spec process_stream(agent(), String.t(), keyword()) ::
          {:ok, Enumerable.t(), agent()} | {:error, term()}
  def process_stream(agent, message, opts \\ []) do
    case ToolsManager.process_stream(agent.conversation_id, message, agent.tools, opts) do
      {:ok, stream} ->
        updated_agent = %{agent | message_count: agent.message_count + 1}
        {:ok, stream, updated_agent}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets conversation statistics for the agent.
  """
  @spec get_statistics(agent()) :: {:ok, map()} | {:error, term()}
  def get_statistics(agent) do
    with {:ok, history} <- ConversationManager.get_messages(agent.conversation_id),
         {:ok, metadata} <- ConversationManager.get_metadata(agent.conversation_id) do
      stats = %{
        conversation_id: agent.conversation_id,
        age_minutes: DateTime.diff(DateTime.utc_now(), agent.created_at, :minute),
        total_messages: metadata.message_count,
        user_messages: count_messages_by_role(history, :user),
        assistant_messages: count_messages_by_role(history, :assistant),
        tool_messages: count_messages_by_role(history, :tool),
        tools_available: length(agent.tools),
        tool_names: Enum.map(agent.tools, &get_tool_name/1)
      }

      {:ok, stats}
    end
  end

  @doc """
  Destroys the agent and cleans up resources.
  """
  @spec destroy_agent(agent()) :: :ok
  def destroy_agent(agent) do
    ConversationManager.delete(agent.conversation_id)
  end

  # Private Functions - Core Logic

  defp process_with_retry(agent, message, retries) when retries > 0 do
    case ToolsManager.process(agent.conversation_id, message, agent.tools, max_iterations: 10) do
      {:ok, response} ->
        {:ok, response}

      {:error, {:llm_error, reason}} ->
        Logger.warning("LLM request failed, retrying: #{inspect(reason)}")
        :timer.sleep(1000)
        process_with_retry(agent, message, retries - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_with_retry(_agent, _message, 0) do
    {:error, :max_retries_exceeded}
  end

  # Private Functions - Scenario Runners

  defp run_scenarios(agent) do
    scenarios = [
      {"Weather Query", "What's the weather in Paris?"},
      {"Calculation", "Calculate 15 * 23"},
      {"Search", "Search for the capital of Japan"},
      {"Multi-step", "What's the weather in Tokyo? Also calculate 100 / 4."}
    ]

    IO.puts(String.duplicate("-", 70))
    IO.puts("\nRunning Conversation Scenarios\n")

    Enum.reduce(scenarios, agent, fn {scenario_name, message}, acc_agent ->
      run_scenario(acc_agent, scenario_name, message)
    end)
  end

  defp run_scenario(agent, scenario_name, message) do
    IO.puts("Scenario: #{scenario_name}")
    IO.puts("   User: #{message}\n")

    start_time = System.monotonic_time(:millisecond)

    case process(agent, message, log: false) do
      {:ok, response, updated_agent} ->
        duration = System.monotonic_time(:millisecond) - start_time
        display_scenario_response(response, duration)
        Process.sleep(300)
        updated_agent

      {:error, reason} ->
        IO.puts("   Error: #{inspect(reason)}\n")
        agent
    end
  end

  defp display_scenario_response(response, duration) do
    content = Map.get(response, :content, "")

    if content != "" do
      preview =
        if String.length(content) > 100 do
          String.slice(content, 0, 100) <> "..."
        else
          content
        end

      IO.puts("   Assistant: #{preview}")
    end

    tool_calls = Map.get(response, :tool_calls_made, 0)

    if tool_calls > 0 do
      IO.puts("   Tool iterations: #{tool_calls}")
    end

    IO.puts("   Duration: #{duration}ms\n")
  end

  # Private Functions - Display

  defp display_agent_info(agent) do
    IO.puts("Agent created successfully\n")
    IO.puts("   ID: #{String.slice(agent.conversation_id, 0, 16)}...")
    IO.puts("   Tools: #{length(agent.tools)}")

    Enum.each(agent.tools, fn tool ->
      IO.puts("      - #{get_tool_name(tool)}")
    end)

    IO.puts("   Temperature: #{agent.options.temperature}")
    IO.puts("   Max Tokens: #{agent.options.max_tokens}\n")
  end

  defp display_final_statistics(agent) do
    IO.puts(String.duplicate("-", 70))
    IO.puts("\nFinal Statistics\n")

    case get_statistics(agent) do
      {:ok, stats} ->
        IO.puts("   Conversation Age: #{stats.age_minutes} minutes")
        IO.puts("   Total Messages: #{stats.total_messages}")
        IO.puts("      - User: #{stats.user_messages}")
        IO.puts("      - Assistant: #{stats.assistant_messages}")
        IO.puts("      - Tool: #{stats.tool_messages}")
        IO.puts("   Tools Available: #{stats.tools_available}")

      {:error, reason} ->
        IO.puts("   Error retrieving statistics: #{inspect(reason)}")
    end
  end

  # Private Functions - Helpers

  defp count_messages_by_role(history, role) do
    Enum.count(history, fn msg -> msg.role == role end)
  end

  defp get_tool_name(tool_module) do
    if function_exported?(tool_module, :name, 0) do
      tool_module.name()
    else
      tool_module |> Module.split() |> List.last()
    end
  end
end

# Mock Actions for demonstration

defmodule Examples.ConversationManager.MockCalculatorAction do
  @moduledoc "Mock calculator action"

  use Jido.Action,
    name: "calculate",
    description: "Perform mathematical calculations",
    schema: [
      expression: [type: :string, required: true, doc: "Mathematical expression to evaluate"]
    ]

  @impl true
  def run(params, _context) do
    expression = params.expression

    result =
      cond do
        expression =~ ~r/\*/ -> parse_and_multiply(expression)
        expression =~ ~r/\// -> parse_and_divide(expression)
        expression =~ ~r/\+/ -> parse_and_add(expression)
        expression =~ ~r/\-/ -> parse_and_subtract(expression)
        true -> {:error, :unsupported_operation}
      end

    case result do
      {:error, reason} -> {:error, reason}
      value -> {:ok, %{expression: expression, result: value}}
    end
  end

  defp parse_and_multiply(expr) do
    case String.split(expr, "*") |> Enum.map(&String.trim/1) do
      [a, b] ->
        with {num1, _} <- Float.parse(a),
             {num2, _} <- Float.parse(b) do
          num1 * num2
        else
          _ -> {:error, :parse_error}
        end

      _ ->
        {:error, :invalid_expression}
    end
  end

  defp parse_and_divide(expr) do
    case String.split(expr, "/") |> Enum.map(&String.trim/1) do
      [a, b] ->
        with {num1, _} <- Float.parse(a),
             {num2, _} <- Float.parse(b) do
          if num2 == 0, do: {:error, :division_by_zero}, else: num1 / num2
        else
          _ -> {:error, :parse_error}
        end

      _ ->
        {:error, :invalid_expression}
    end
  end

  defp parse_and_add(expr) do
    case String.split(expr, "+") |> Enum.map(&String.trim/1) do
      [a, b] ->
        with {num1, _} <- Float.parse(a),
             {num2, _} <- Float.parse(b) do
          num1 + num2
        else
          _ -> {:error, :parse_error}
        end

      _ ->
        {:error, :invalid_expression}
    end
  end

  defp parse_and_subtract(expr) do
    case String.split(expr, "-") |> Enum.map(&String.trim/1) do
      [a, b] ->
        with {num1, _} <- Float.parse(a),
             {num2, _} <- Float.parse(b) do
          num1 - num2
        else
          _ -> {:error, :parse_error}
        end

      _ ->
        {:error, :invalid_expression}
    end
  end
end

defmodule Examples.ConversationManager.MockSearchAction do
  @moduledoc "Mock search action"

  use Jido.Action,
    name: "search",
    description: "Search for information on a topic",
    schema: [
      query: [type: :string, required: true, doc: "Search query"]
    ]

  @impl true
  def run(params, _context) do
    query = String.downcase(params.query)

    results =
      cond do
        query =~ ~r/capital.*japan/ ->
          [%{title: "Tokyo - Capital of Japan", snippet: "Tokyo is the capital city of Japan"}]

        query =~ ~r/capital.*france/ ->
          [%{title: "Paris - Capital of France", snippet: "Paris is the capital city of France"}]

        query =~ ~r/weather/ ->
          [%{title: "Weather Services", snippet: "Check current weather conditions"}]

        true ->
          [%{title: "Search Results", snippet: "General results for: #{params.query}"}]
      end

    {:ok, %{query: params.query, results: results, count: length(results)}}
  end
end
