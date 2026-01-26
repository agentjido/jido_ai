defmodule Jido.AI.Skills.Planning.Actions.Prioritize do
  @moduledoc """
  A Jido.Action for prioritizing tasks based on given criteria.

  This action uses ReqLLM with a specialized system prompt for task prioritization,
  analyzing and ordering tasks according to their importance, urgency, and dependencies.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:planning`) or direct spec
  * `tasks` (required) - List of tasks to prioritize
  * `criteria` (optional) - Prioritization criteria (e.g., "impact", "urgency", "effort")
  * `context` (optional) - Additional context about the project
  * `max_tokens` (optional) - Maximum tokens to generate (default: `4096`)
  * `temperature` (optional) - Sampling temperature (default: `0.5`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic prioritization
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Planning.Actions.Prioritize, %{
        tasks: [
          "Fix critical bug",
          "Update documentation",
          "Refactor authentication",
          "Add new feature"
        ]
      })

      # With specific criteria
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Planning.Actions.Prioritize, %{
        tasks: ["Task A", "Task B", "Task C"],
        criteria: "Business impact, development effort, and dependencies"
      })

      # With context
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Planning.Actions.Prioritize, %{
        tasks: ["Design database", "Build API", "Create UI"],
        criteria: "Dependencies and value delivery",
        context: "Early-stage startup, need MVP quickly"
      })
  """

  use Jido.Action,
    name: "planning_prioritize",
    description: "Prioritize and order tasks based on given criteria",
    category: "ai",
    tags: ["planning", "prioritization", "tasks"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        model:
          Zoi.string(description: "Model spec (e.g., 'anthropic:claude-sonnet-4-20250514') or alias (e.g., :planning)")
          |> Zoi.optional(),
        tasks: Zoi.list(Zoi.string(), description: "List of tasks to prioritize"),
        criteria:
          Zoi.string(description: "Prioritization criteria (e.g., 'impact, urgency, effort')")
          |> Zoi.optional(),
        context: Zoi.string(description: "Additional context about the project") |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(4096),
        temperature: Zoi.float(description: "Sampling temperature") |> Zoi.default(0.5),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Config
  alias Jido.AI.Helpers

  @prioritization_prompt """
  You are an expert project manager specializing in task prioritization.

  Your task is to analyze the given list of tasks and prioritize them based on the provided criteria.
  Consider factors such as:

  1. **Dependencies** - Which tasks must be completed before others?
  2. **Impact** - Which tasks deliver the most value?
  3. **Urgency** - Which tasks have deadlines or time sensitivity?
  4. **Effort** - Which tasks provide good ROI for the effort required?
  5. **Risk** - Which tasks mitigate significant risks if done early?

  Format your prioritization as follows:

  ## Priority Analysis

  ### High Priority (Do First)
  1. **[Task Name]** - Score: [8-10]
     - **Reasoning**: [Why this is top priority]
     - **Dependencies**: [What this enables]
     - **Estimated Effort**: [Low/Medium/High]

  ### Medium Priority (Do Second)
  2. **[Task Name]** - Score: [5-7]
     - **Reasoning**: [Why this is medium priority]
     - **Dependencies**: [What this enables]
     - **Estimated Effort**: [Low/Medium/High]

  ### Low Priority (Do Last)
  3. **[Task Name]** - Score: [1-4]
     - **Reasoning**: [Why this is lower priority]
     - **Dependencies**: [What this enables]
     - **Estimated Effort**: [Low/Medium/High]

  ## Recommended Execution Order
  1. [Task 1] → 2. [Task 2] → 3. [Task 3] → ...

  ## Rationale
  [Explain the overall strategy behind this ordering]

  Be objective and consistent in your scoring. Explain trade-offs clearly.
  """

  @doc """
  Executes the prioritize action.

  ## Returns

  * `{:ok, result}` - Successful response with `prioritization`, `ordered_tasks`, `scores`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        prioritization: "The full prioritization analysis",
        ordered_tasks: ["Task 1", "Task 2", ...],
        scores: %{"Task 1" => 9, "Task 2" => 7, ...},
        model: "anthropic:claude-sonnet-4-20250514",
        usage: %{...}
      }
  """
  @impl Jido.Action
  def run(params, _context) do
    with :ok <- validate_tasks(params[:tasks]),
         {:ok, model} <- resolve_model(params[:model]),
         context = build_prioritize_messages(params),
         opts = build_opts(params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, context.messages, opts) do
      {:ok, format_result(response, model)}
    end
  end

  # Private Functions

  defp validate_tasks(nil), do: {:error, :tasks_required}
  defp validate_tasks([]), do: {:error, :tasks_cannot_be_empty}
  defp validate_tasks(tasks) when is_list(tasks), do: :ok
  defp validate_tasks(_), do: {:error, :invalid_tasks_format}

  defp resolve_model(nil), do: {:ok, Config.resolve_model(:planning)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Config.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}

  defp build_prioritize_messages(params) do
    user_prompt = build_prioritize_user_prompt(params)
    Helpers.build_messages(user_prompt, system_prompt: @prioritization_prompt)
  end

  defp build_prioritize_user_prompt(params) do
    tasks_list =
      params[:tasks]
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {task, i} -> "#{i}. #{task}" end)

    base = "Tasks to prioritize:\n#{tasks_list}"

    base =
      case params[:criteria] do
        nil ->
          base

        criteria when is_binary(criteria) ->
          base <> "\n\nPrioritization Criteria:\n" <> criteria
      end

    base =
      case params[:context] do
        nil ->
          base

        context when is_binary(context) ->
          base <> "\n\nProject Context:\n" <> context
      end

    base
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

  defp format_result(response, model) do
    prioritization_text = extract_text(response)

    %{
      prioritization: prioritization_text,
      ordered_tasks: extract_ordered_tasks(prioritization_text),
      scores: extract_scores(prioritization_text),
      model: model,
      usage: extract_usage(response)
    }
  end

  defp extract_ordered_tasks(text) do
    # Extract tasks from the "Recommended Execution Order" section
    case Regex.run(~r/Recommended Execution Order\s+(.+?)(?:\n\n|\z)/s, text) do
      nil ->
        []

      [_, order_section] ->
        parse_ordered_tasks(order_section)
    end
  end

  defp parse_ordered_tasks(order_section) do
    order_section
    |> String.split("\n")
    |> Enum.map(&extract_task_from_line/1)
    |> Enum.filter(fn t -> t != nil end)
  end

  defp extract_task_from_line(line) do
    case Regex.run(~r/^\d+\.\s+\*\*(.+?)\*\*/, line) do
      [_, task] -> String.trim(task)
      _ -> nil
    end
  end

  defp extract_scores(text) do
    # Extract scores from priority sections
    Regex.scan(~r/^\d+\.\s+\*\*(.+?)\*\*\s+-\s+Score:\s+\((\d+)\)/m, text)
    |> Map.new(fn [_, task, score] ->
      {String.trim(task), String.to_integer(score)}
    end)
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
