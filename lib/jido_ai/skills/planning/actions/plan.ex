defmodule Jido.AI.Skills.Planning.Actions.Plan do
  @moduledoc """
  A Jido.Action for generating structured plans from goals.

  This action uses ReqLLM with a specialized system prompt for planning,
  generating step-by-step plans that consider constraints and available resources.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:planning`) or direct spec
  * `goal` (required) - The goal to achieve
  * `constraints` (optional) - List of constraints/limitations
  * `resources` (optional) - List of available resources
  * `max_steps` (optional) - Maximum number of steps in the plan (default: `10`)
  * `max_tokens` (optional) - Maximum tokens to generate (default: `4096`)
  * `temperature` (optional) - Sampling temperature (default: `0.7`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic planning
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Planning.Actions.Plan, %{
        goal: "Build a personal blog website"
      })

      # With constraints and resources
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Planning.Actions.Plan, %{
        goal: "Launch a SaaS product",
        constraints: ["Budget under $10k", "Must launch in 3 months"],
        resources: ["2 developers", "Existing customer base"],
        max_steps: 15
      })
  """

  use Jido.Action,
    name: "planning_plan",
    description: "Generate a structured plan from a goal with constraints and resources",
    category: "ai",
    tags: ["planning", "goals"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        model:
          Zoi.string(description: "Model spec (e.g., 'anthropic:claude-sonnet-4-20250514') or alias (e.g., :planning)")
          |> Zoi.optional(),
        goal: Zoi.string(description: "The goal to achieve"),
        constraints:
          Zoi.list(Zoi.string(), description: "List of constraints/limitations")
          |> Zoi.optional(),
        resources:
          Zoi.list(Zoi.string(), description: "List of available resources")
          |> Zoi.optional(),
        max_steps: Zoi.integer(description: "Maximum number of steps in the plan") |> Zoi.default(10),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(4096),
        temperature: Zoi.float(description: "Sampling temperature") |> Zoi.default(0.7),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Config
  alias Jido.AI.Helpers

  @planning_prompt """
  You are an expert strategic planner. Your task is to create detailed, actionable plans to achieve goals.

  For the provided goal, create a structured plan that:
  1. Breaks down the goal into clear, sequential steps
  2. Considers any stated constraints and limitations
  3. Makes effective use of available resources
  4. Identifies dependencies between steps
  5. Includes milestones for tracking progress

  Format your plan as follows:

  ## Plan Overview
  [Brief summary of the approach]

  ## Steps
  1. **[Step Name]**
     - Description: [What needs to be done]
     - Dependencies: [Any prerequisites]
     - Resources needed: [Required resources]
     - Estimated effort: [Relative effort level]

  2. **[Step Name]**
     ... (continue for each step)

  ## Milestones
  - [Milestone 1]: [When it occurs]
  - [Milestone 2]: [When it occurs]

  ## Risks and Considerations
  - [Potential risks]: [Mitigation strategies]

  Be specific, realistic, and actionable. Focus on steps that are clear and achievable.
  """

  @doc """
  Executes the plan action.

  ## Returns

  * `{:ok, result}` - Successful response with `plan`, `steps`, `goal`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        plan: "The full plan text",
        steps: ["Step 1", "Step 2", ...],
        goal: "The original goal",
        model: "anthropic:claude-sonnet-4-20250514",
        usage: %{...}
      }
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, model} <- resolve_model(params[:model]),
         {:ok, context} <- build_plan_messages(params),
         opts = build_opts(params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, context.messages, opts) do
      {:ok, format_result(response, model, params[:goal])}
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Config.resolve_model(:planning)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Config.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}

  defp build_plan_messages(params) do
    user_prompt = build_plan_user_prompt(params)
    Helpers.build_messages(user_prompt, system_prompt: @planning_prompt)
  end

  defp build_plan_user_prompt(params) do
    base = "Goal: #{params[:goal]}"

    base =
      case params[:constraints] do
        nil ->
          base

        [] ->
          base

        constraints when is_list(constraints) ->
          constraints_str = Enum.join(constraints, "\n- ")
          base <> "\n\nConstraints:\n- " <> constraints_str
      end

    base =
      case params[:resources] do
        nil ->
          base

        [] ->
          base

        resources when is_list(resources) ->
          resources_str = Enum.join(resources, "\n- ")
          base <> "\n\nAvailable Resources:\n- " <> resources_str
      end

    max_steps = params[:max_steps] || 10
    base <> "\n\nPlease create a plan with approximately #{max_steps} steps."
  end

  defp build_opts(params) do
    opts = [
      max_tokens: params[:max_tokens],
      temperature: params[:temperature]
    ]

    opts =
      if params[:timeout] do
        Keyword.put(opts, :receive_timeout, params[:timeout])
      else
        opts
      end

    opts
  end

  defp format_result(response, model, goal) do
    plan_text = extract_text(response)

    %{
      plan: plan_text,
      steps: extract_steps(plan_text),
      goal: goal,
      model: model,
      usage: extract_usage(response)
    }
  end

  defp extract_steps(plan_text) do
    # Extract numbered steps from the plan
    Regex.scan(~r/^\d+\.\s+\*\*(.*?)\*\*/m, plan_text)
    |> Enum.map(fn [_, name] -> name end)
  end

  defp extract_text(%{message: %{content: content}}) do
    case content do
      c when is_binary(c) ->
        c

      c when is_list(c) ->
        c
        |> Enum.filter(fn
          %{type: :text} -> true
          _ -> false
        end)
        |> Enum.map_join("", fn
          %{text: text} -> text
          _ -> ""
        end)

      _ ->
        ""
    end
  end

  @dialyzer {:nowarn_function, extract_text: 1}

  defp extract_text(_), do: ""

  defp extract_usage(%{usage: usage}) when is_map(usage) do
    %{
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      total_tokens: Map.get(usage, :total_tokens, 0)
    }
  end

  defp extract_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
end
