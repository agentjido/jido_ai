defmodule Jido.AI.Actions.Orchestration.DelegateTask do
  @moduledoc """
  LLM-powered task delegation to specialist agents.

  This action uses an LLM to decide how to route a task - either execute
  locally or delegate to a specialist agent based on capabilities.

  ## Parameters

  * `task` (required) - Task description to route
  * `available_agents` (required) - List of agent capability descriptors
  * `model` (optional) - Model to use for routing decision
  * `mode` (optional) - `:spawn`, `:reuse`, or `:auto` (default: `:auto`)

  ## Agent Capability Descriptor

  Each agent in `available_agents` should have:

      %{
        name: "document_analyzer",
        description: "Analyzes PDF and text documents",
        capabilities: ["pdf_parsing", "summarization"],
        agent_module: MyApp.DocumentAgent  # optional
      }

  ## Examples

      {:ok, result} = Jido.Exec.run(DelegateTask, %{
        task: "Analyze this PDF document",
        available_agents: [
          %{name: "doc_analyzer", capabilities: ["pdf", "analysis"], agent_module: DocAgent},
          %{name: "code_reviewer", capabilities: ["code", "review"], agent_module: CodeAgent}
        ]
      })

  ## Result

      # When delegating:
      %{
        decision: :delegate,
        target: %{name: "doc_analyzer", agent_module: DocAgent},
        reasoning: "Task involves PDF analysis..."
      }

      # When handling locally:
      %{
        decision: :local,
        reasoning: "No specialist matches this task..."
      }
  """

  use Jido.Action,
    name: "delegate_task",
    description: "LLM-powered task delegation to specialist agents",
    category: "orchestration",
    tags: ["orchestration", "delegation", "routing", "llm"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        task: Zoi.string(description: "Task description to route"),
        available_agents: Zoi.list(Zoi.map(), description: "List of agent capability descriptors"),
        model: Zoi.string(description: "Model for routing decision") |> Zoi.optional(),
        mode: Zoi.any(description: "Routing mode: :spawn, :reuse, or :auto") |> Zoi.default(:auto)
      })

  alias Jido.AI.Actions.Helpers

  @routing_prompt """
  You are a task router. Given a task and available specialist agents, decide the best routing.

  TASK: <%= task %>

  AVAILABLE AGENTS:
  <%= for agent <- agents do %>
  - <%= agent.name %>: <%= agent[:description] || "No description" %>
    Capabilities: <%= Enum.join(agent[:capabilities] || [], ", ") %>
  <% end %>

  Respond with JSON:
  {
    "decision": "delegate" or "local",
    "target_name": "agent name if delegating, null otherwise",
    "reasoning": "brief explanation"
  }

  Choose "delegate" if a specialist clearly matches. Choose "local" if no good match or task is simple.
  """

  @impl Jido.Action
  def run(params, _context) do
    with {:ok, model} <- Helpers.resolve_model(params[:model], :fast),
         prompt = build_routing_prompt(params.task, params.available_agents),
         {:ok, response} <- call_llm(model, prompt),
         {:ok, routing} <- parse_routing_response(response) do
      build_result(routing, params.available_agents)
    end
  end

  defp build_routing_prompt(task, agents) do
    EEx.eval_string(@routing_prompt, task: task, agents: agents)
  end

  defp call_llm(model, prompt) do
    # Use a prompt that requests JSON output instead of provider-specific options
    json_prompt = prompt <> "\n\nRespond ONLY with valid JSON, no other text."

    case ReqLLM.Generation.generate_text(model, [%{role: :user, content: json_prompt}]) do
      {:ok, response} ->
        text = Helpers.extract_text(response)
        {:ok, text}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_routing_response(text) do
    # Extract JSON from markdown code blocks if present
    clean_text = extract_json_from_markdown(text)

    case Jason.decode(clean_text) do
      {:ok, %{"decision" => decision} = parsed} ->
        case parse_decision(decision) do
          {:ok, parsed_decision} ->
            {:ok, Map.put(parsed, "decision", parsed_decision)}

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

  defp extract_json_from_markdown(text) do
    # Try to extract JSON from markdown code blocks
    case Regex.run(~r/```(?:json)?\s*([\s\S]*?)```/m, text) do
      [_, json] -> String.trim(json)
      nil -> String.trim(text)
    end
  end

  defp build_result(%{"decision" => :delegate, "target_name" => target_name} = routing, agents) do
    target = Enum.find(agents, fn a -> a[:name] == target_name end)

    {:ok,
     %{
       decision: :delegate,
       target: target,
       reasoning: routing["reasoning"]
     }}
  end

  defp build_result(%{"decision" => :local} = routing, _agents) do
    {:ok,
     %{
       decision: :local,
       reasoning: routing["reasoning"]
     }}
  end

  defp build_result(_, _), do: {:error, :invalid_routing_decision}
end
