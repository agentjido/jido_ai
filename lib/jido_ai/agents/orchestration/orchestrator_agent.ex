defmodule Jido.AI.OrchestratorAgent do
  @moduledoc """
  Base macro for Orchestrator agents that coordinate specialist child agents.

  Creates a parent agent that uses LLM-powered delegation to route tasks
  to appropriate specialist agents based on their capabilities.

  ## Usage

      defmodule MyApp.TeamOrchestrator do
        use Jido.AI.OrchestratorAgent,
          name: "team_orchestrator",
          description: "Coordinates specialist agents",
          specialists: [
            %{
              name: "math_specialist",
              description: "Handles mathematical calculations",
              capabilities: ["arithmetic", "math", "calculation"],
              tools: [Jido.Tools.Arithmetic.Add, Jido.Tools.Arithmetic.Multiply]
            },
            %{
              name: "weather_specialist",
              description: "Provides weather information",
              capabilities: ["weather", "forecast", "temperature"],
              tools: [Jido.Tools.Weather]
            }
          ]
      end

  ## Options

  - `:name` (required) - Agent name
  - `:specialists` (required) - List of specialist definitions
  - `:description` - Agent description
  - `:model` - Model for orchestration decisions (default: "anthropic:claude-haiku-4-5")
  - `:system_prompt` - Custom system prompt
  - `:max_iterations` - Max iterations per specialist (default: 10)

  ## Specialist Definition

  Each specialist in the `:specialists` list should have:

  - `:name` - Unique name for the specialist
  - `:description` - What this specialist does
  - `:capabilities` - List of capability keywords for routing
  - `:tools` - List of Jido.Action modules the specialist can use

  ## How It Works

  1. Query arrives at the orchestrator
  2. Orchestrator uses DelegateTask to analyze the query
  3. LLM decides: delegate to a specialist or handle locally
  4. If delegating: spawns specialist, forwards query, aggregates result
  5. Returns final answer to caller

  ## Example

      {:ok, pid} = Jido.start_agent(MyJido, MyApp.TeamOrchestrator)
      :ok = MyApp.TeamOrchestrator.ask(pid, "What is 15 * 7?")

      # Orchestrator delegates to math_specialist
      agent = Jido.AgentServer.get(pid)
      agent.state.last_answer  # => "105"
  """

  alias Jido.AI.ReActAgent

  @default_model "anthropic:claude-haiku-4-5"
  @default_max_iterations 10

  defmacro __using__(opts) do
    name = Keyword.fetch!(opts, :name)
    specialists_ast = Keyword.fetch!(opts, :specialists)
    description = Keyword.get(opts, :description, "Orchestrator agent #{name}")
    model = Keyword.get(opts, :model, @default_model)
    system_prompt = Keyword.get(opts, :system_prompt)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)

    # Evaluate specialists at compile time, expanding module aliases
    specialists =
      specialists_ast
      |> Enum.map(fn spec_ast ->
        # Use the same safe AST expansion as ReActAgent
        expanded = ReActAgent.expand_aliases_in_ast(spec_ast, __CALLER__)
        {spec, _} = Code.eval_quoted(expanded, [], __CALLER__)
        spec
      end)

    quote location: :keep do
      use Jido.AI.Agent,
        name: unquote(name),
        description: unquote(description),
        plugins: [
          Jido.AI.Plugins.TaskSupervisor,
          {Jido.AI.Plugins.Orchestration, []}
        ],
        strategy:
          {Jido.AI.Strategies.ReAct,
           [
             tools: [Jido.AI.OrchestratorAgent.DelegateAndExecute],
             model: unquote(model),
             max_iterations: unquote(max_iterations),
             system_prompt: unquote(system_prompt) || unquote(__MODULE__).default_system_prompt(),
             tool_context: %{specialists: unquote(Macro.escape(specialists))}
           ]},
        schema:
          Zoi.object(%{
            __strategy__: Zoi.map() |> Zoi.default(%{}),
            model: Zoi.string() |> Zoi.default(unquote(model)),
            specialists: Zoi.list(Zoi.map()) |> Zoi.default(unquote(Macro.escape(specialists))),
            last_query: Zoi.string() |> Zoi.default(""),
            last_answer: Zoi.string() |> Zoi.default(""),
            completed: Zoi.boolean() |> Zoi.default(false)
          })

      @specialists unquote(Macro.escape(specialists))

      def specialists, do: @specialists

      def cli_adapter, do: Jido.AI.CLI.Adapters.ReAct

      def ask(pid, query, opts \\ []) when is_binary(query) do
        tool_context =
          opts
          |> Keyword.get(:tool_context, %{})
          |> Map.put(:specialists, @specialists)

        payload = %{query: query, tool_context: tool_context}
        signal = Jido.Signal.new!("react.input", payload, source: "/orchestrator/agent")
        Jido.AgentServer.cast(pid, signal)
      end

      @impl true
      def on_before_cmd(agent, {:react_start, %{query: query}} = action) do
        agent = %{
          agent
          | state:
              agent.state
              |> Map.put(:last_query, query)
              |> Map.put(:completed, false)
              |> Map.put(:last_answer, "")
        }

        {:ok, agent, action}
      end

      @impl true
      def on_before_cmd(agent, action), do: {:ok, agent, action}

      @impl true
      def on_after_cmd(agent, _action, directives) do
        snap = strategy_snapshot(agent)

        agent =
          if snap.done? do
            %{
              agent
              | state:
                  Map.merge(agent.state, %{
                    last_answer: snap.result || "",
                    completed: true
                  })
            }
          else
            agent
          end

        {:ok, agent, directives}
      end

      defoverridable on_before_cmd: 2, on_after_cmd: 3
    end
  end

  def default_system_prompt do
    """
    You are an orchestrator agent that MUST delegate all tasks to specialist agents.

    IMPORTANT: You do NOT answer questions directly. You ALWAYS use the delegate_and_execute
    tool to route tasks to specialists. Even for simple tasks, you MUST delegate.

    Your ONLY job is to:
    1. Receive the user's query
    2. Call delegate_and_execute with the exact query as the task parameter
    3. Report the result from the specialist

    You have specialist agents for:
    - Math/calculations (math_specialist)
    - Weather information (weather_specialist)

    NEVER calculate or answer anything yourself. ALWAYS use the delegate_and_execute tool.
    """
  end
end

defmodule Jido.AI.OrchestratorAgent.DelegateAndExecute do
  @moduledoc """
  Combined delegation and execution tool for the orchestrator.

  This action:
  1. Uses DelegateTask to decide routing (LLM-powered)
  2. If delegating: creates an ephemeral specialist ReAct agent and runs the query
  3. Returns the result from the specialist or handles locally
  """

  use Jido.Action,
    name: "delegate_and_execute",
    description: "Analyze a task and delegate to the best specialist agent, then return the result",
    category: "orchestration",
    tags: ["orchestration", "delegation", "routing"],
    schema:
      Zoi.object(%{
        task: Zoi.string(description: "The task or query to delegate and execute")
      })

  require Logger
  @specialist_jido_instance JidoAi.OrchestratorSpecialistJido
  @specialist_timeout_ms 30_000

  @impl Jido.Action
  def run(params, context) do
    task = params.task
    specialists = get_specialists(context)

    Logger.debug("[DelegateAndExecute] Starting delegation",
      task: task,
      specialist_count: length(specialists)
    )

    if Enum.empty?(specialists) do
      {:ok, %{result: "No specialists available. Task: #{task}", delegated_to: nil}}
    else
      with {:ok, routing} <- route_task(task, specialists) do
        execute_routing(routing, task, specialists)
      end
    end
  end

  defp get_specialists(context) do
    # The tool_context from the strategy IS the context passed to the action
    # So specialists are at context[:specialists], not context[:tool_context][:specialists]
    specialists = context[:specialists] || context[:tool_context][:specialists] || []
    Logger.debug("[DelegateAndExecute] Found specialists", specialist_count: length(specialists))
    specialists
  end

  defp route_task(task, specialists) do
    available_agents =
      Enum.map(specialists, fn spec ->
        %{
          name: spec[:name],
          description: spec[:description],
          capabilities: spec[:capabilities] || []
        }
      end)

    # Use a custom prompt that strongly prefers delegation
    prompt = build_delegation_prompt(task, available_agents)

    case call_routing_llm(prompt) do
      {:ok, routing} -> {:ok, routing}
      {:error, _} = error -> error
    end
  end

  defp build_delegation_prompt(task, agents) do
    agent_list =
      Enum.map_join(agents, "\n", fn agent ->
        caps = Enum.join(agent[:capabilities] || [], ", ")
        "- #{agent.name}: #{agent[:description] || "No description"}\n  Capabilities: #{caps}"
      end)

    """
    You are a task router for a multi-agent system. You MUST delegate tasks to specialists.

    TASK: #{task}

    AVAILABLE SPECIALISTS:
    #{agent_list}

    RULES:
    1. ALWAYS delegate if ANY specialist has relevant capabilities
    2. Only choose "local" if NO specialist matches at all
    3. For math/calculation tasks, delegate to math specialists
    4. For weather tasks, delegate to weather specialists

    Respond with ONLY valid JSON:
    {"decision": "delegate", "target_name": "specialist name", "reasoning": "brief explanation"}

    OR if truly no match:
    {"decision": "local", "target_name": null, "reasoning": "explanation"}
    """
  end

  defp call_routing_llm(prompt) do
    # Use the fast model for routing decisions
    model = Jido.AI.resolve_model(:fast)

    case ReqLLM.Generation.generate_text(model, [%{role: :user, content: prompt}]) do
      {:ok, response} ->
        text = extract_text(response)
        Logger.debug("[Routing] LLM response received", response_length: String.length(text))
        parse_routing_response(text)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec extract_text(ReqLLM.Response.t()) :: binary()
  defp extract_text(%ReqLLM.Response{message: nil}), do: ""

  defp extract_text(%ReqLLM.Response{message: %ReqLLM.Message{content: content}}) do
    extract_content(content)
  end

  @spec extract_content([map()]) :: binary()
  defp extract_content([%{text: text} | _]) when is_binary(text), do: text
  defp extract_content([%{"text" => text} | _]) when is_binary(text), do: text
  defp extract_content([]), do: ""
  defp extract_content(other), do: inspect(other)

  defp parse_routing_response(text) do
    clean_text =
      case Regex.run(~r/```(?:json)?\s*([\s\S]*?)```/m, text) do
        [_, json] -> String.trim(json)
        nil -> String.trim(text)
      end

    case Jason.decode(clean_text) do
      {:ok, %{"decision" => decision, "target_name" => target_name} = parsed} ->
        case parse_decision(decision) do
          {:ok, parsed_decision} ->
            {:ok,
             %{
               decision: parsed_decision,
               target: if(target_name, do: %{name: target_name}),
               reasoning: parsed["reasoning"]
             }}

          :error ->
            {:error, :invalid_routing_decision}
        end

      {:ok, _} ->
        {:error, :invalid_routing_response}

      {:error, _} ->
        {:error, :json_parse_failed}
    end
  end

  defp parse_decision("delegate"), do: {:ok, :delegate}
  defp parse_decision("local"), do: {:ok, :local}
  defp parse_decision(:delegate), do: {:ok, :delegate}
  defp parse_decision(:local), do: {:ok, :local}
  defp parse_decision(_), do: :error

  defp execute_routing(%{decision: :local, reasoning: reasoning}, task, _specialists) do
    {:ok,
     %{
       result: "Handled locally: #{task}. Reasoning: #{reasoning}",
       delegated_to: nil,
       reasoning: reasoning
     }}
  end

  defp execute_routing(%{decision: :delegate, target: target, reasoning: reasoning}, task, specialists) do
    specialist_name = target[:name]
    specialist = Enum.find(specialists, fn s -> s[:name] == specialist_name end)

    if specialist do
      case run_specialist(specialist, task) do
        {:ok, answer} ->
          {:ok,
           %{
             result: answer,
             delegated_to: specialist_name,
             reasoning: reasoning
           }}

        {:error, reason} ->
          {:error, "Specialist #{specialist_name} failed: #{inspect(reason)}"}
      end
    else
      {:error, "Specialist #{specialist_name} not found"}
    end
  end

  defp run_specialist(specialist, task) do
    spec_name = specialist[:name] || "unnamed"

    try do
      with :ok <- ensure_specialist_instance_started() do
        module_name = ensure_specialist_module(specialist)

        Logger.debug("[Orchestrator] Starting specialist agent",
          module_name: module_name,
          specialist_name: spec_name
        )

        agent_id = "specialist-#{:erlang.unique_integer([:positive])}"

        case Jido.start_agent(@specialist_jido_instance, module_name, id: agent_id) do
          {:ok, pid} ->
            Logger.debug("[Orchestrator] Agent started", agent_pid: pid, task: task)
            :ok = module_name.ask(pid, task)
            result = await_specialist(pid, @specialist_timeout_ms)
            Logger.debug("[Orchestrator] Specialist completed", result_type: result_type(result))
            stop_specialist_agent(pid)
            result

          {:error, reason} ->
            Logger.error("[Orchestrator] Failed to start agent", reason: reason)
            {:error, reason}
        end
      end
    rescue
      e ->
        Logger.error("[Orchestrator] Exception in specialist",
          exception_message: Exception.message(e),
          exception_type: e.__struct__
        )

        {:error, Exception.message(e)}
    end
  end

  defp ensure_specialist_instance_started do
    case Jido.start_link(name: @specialist_jido_instance) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_specialist_module(specialist) do
    module_id =
      :erlang.phash2({
        specialist[:name],
        specialist[:description],
        specialist[:tools],
        specialist[:model]
      })

    module_name = Module.concat([JidoAi, OrchestratorSpecialist, :"Spec#{module_id}"])

    if Code.ensure_loaded?(module_name) do
      module_name
    else
      tools = specialist[:tools] || []
      model = specialist[:model] || "anthropic:claude-haiku-4-5"
      spec_name = specialist[:name] || "unnamed"

      contents =
        quote do
          use Jido.AI.ReActAgent,
            name: unquote(spec_name),
            description: unquote(specialist[:description] || "Specialist agent"),
            tools: unquote(tools),
            model: unquote(model),
            max_iterations: 5
        end

      try do
        Module.create(module_name, contents, Macro.Env.location(__ENV__))
      rescue
        ArgumentError ->
          :ok
      end

      module_name
    end
  end

  defp stop_specialist_agent(pid) when is_pid(pid) do
    GenServer.stop(pid, :normal, 1000)
    :ok
  catch
    :exit, _ -> :ok
  end

  defp await_specialist(pid, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    poll_specialist(pid, deadline)
  end

  defp poll_specialist(pid, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      {:error, :timeout}
    else
      case Jido.AgentServer.status(pid) do
        {:ok, status} ->
          handle_specialist_status(status, pid, deadline)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp handle_specialist_status(status, pid, deadline) do
    if status.snapshot.done? do
      {:ok, extract_specialist_answer(status)}
    else
      Process.sleep(100)
      poll_specialist(pid, deadline)
    end
  end

  defp extract_specialist_answer(status) do
    case status.snapshot.result do
      nil -> Map.get(status.raw_state, :last_answer, "")
      "" -> Map.get(status.raw_state, :last_answer, "")
      result -> result
    end
  end

  defp result_type({:ok, _}), do: :ok
  defp result_type({:error, _}), do: :error
end
