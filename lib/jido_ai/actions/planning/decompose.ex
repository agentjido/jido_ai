defmodule Jido.AI.Actions.Planning.Decompose do
  @moduledoc """
  A Jido.Action for breaking down complex goals into hierarchical sub-goals.

  This action uses ReqLLM with a specialized system prompt for goal decomposition,
  creating hierarchical structures that break complex goals into manageable pieces.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:planning`) or direct spec
  * `goal` (required) - The goal to decompose
  * `max_depth` (optional) - Maximum depth of decomposition (default: `3`)
  * `context` (optional) - Additional context about the goal
  * `max_tokens` (optional) - Maximum tokens to generate (default: `4096`)
  * `temperature` (optional) - Sampling temperature (default: `0.6`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic decomposition
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Planning.Decompose, %{
        goal: "Build a mobile app"
      })

      # With specific depth
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Planning.Decompose, %{
        goal: "Launch a startup",
        max_depth: 4
      })

      # With context
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Planning.Decompose, %{
        goal: "Organize a conference",
        context: "Technology conference with 500 attendees, limited budget"
      })
  """

  use Jido.Action,
    name: "planning_decompose",
    description: "Break down complex goals into hierarchical sub-goals",
    category: "ai",
    tags: ["planning", "decomposition", "goals"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :planning) or direct model spec string")
          |> Zoi.optional(),
        goal: Zoi.string(description: "The goal to decompose"),
        max_depth: Zoi.integer(description: "Maximum depth of decomposition (1-5)") |> Zoi.default(3),
        context: Zoi.string(description: "Additional context about the goal") |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(4096),
        temperature: Zoi.float(description: "Sampling temperature") |> Zoi.default(0.6),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Actions.Helpers
  alias Jido.AI.Turn
  alias ReqLLM.Context

  @decomposition_prompt """
  You are an expert at breaking down complex goals into manageable components.

  Your task is to decompose the given goal into a hierarchical structure of sub-goals.
  Each level should break down goals into actionable pieces that are easier to accomplish.

  Structure your decomposition using the following format:

  ## Level 1: Main Goal Areas
  ### 1. [Area Name]
  - **Purpose**: [Why this area matters]
  - **Sub-goals**:
    - 1.1. [Sub-goal 1]
    - 1.2. [Sub-goal 2]

  ### 2. [Area Name]
  - **Purpose**: [Why this area matters]
  - **Sub-goals**:
    - 2.1. [Sub-goal 1]
    - 2.2. [Sub-goal 2]

  ## Level 2: Detailed Breakdown
  [For key sub-goals, break them down further with specific tasks]

  ## Dependencies
  - [Identify which sub-goals depend on others]

  ## Success Criteria
  - [How to know when each sub-goal is achieved]

  Guidelines:
  - Each sub-goal should be specific and measurable
  - Sub-goals at the same level should be roughly equal in scope
  - Identify clear dependencies between sub-goals
  - Keep the decomposition practical and actionable
  """

  @doc """
  Executes the decompose action.

  ## Returns

  * `{:ok, result}` - Successful response with `decomposition`, `sub_goals`, `goal`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        decomposition: "The full decomposition text",
        sub_goals: ["Sub-goal 1", "Sub-goal 2", ...],
        goal: "The original goal",
        depth: 3,
        model: "anthropic:claude-sonnet-4-20250514",
        usage: %{...}
      }
  """
  @impl Jido.Action
  def run(params, context) do
    params = apply_context_defaults(params, context)

    with {:ok, model} <- resolve_model(params[:model]),
         {:ok, req_context} <- build_decompose_messages(params),
         opts = build_opts(params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, req_context.messages, opts) do
      {:ok, format_result(response, model, params[:goal], clamp_depth(params[:max_depth] || 3))}
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Jido.AI.resolve_model(:planning)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Jido.AI.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}

  defp build_decompose_messages(params) do
    user_prompt = build_decompose_user_prompt(params)
    Context.normalize(user_prompt, system_prompt: @decomposition_prompt)
  end

  defp build_decompose_user_prompt(params) do
    base = "Goal to decompose: #{params[:goal]}"

    base =
      case params[:context] do
        nil ->
          base

        context when is_binary(context) ->
          base <> "\n\nContext:\n" <> context
      end

    max_depth = clamp_depth(params[:max_depth] || 3)
    base <> "\n\nPlease decompose this goal to a maximum depth of #{max_depth} levels."
  end

  defp clamp_depth(depth) when is_integer(depth), do: max(1, min(depth, 5))
  defp clamp_depth(_), do: 3

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

  defp format_result(response, model, goal, depth) do
    decomposition_text = Turn.extract_text(response)

    %{
      decomposition: decomposition_text,
      sub_goals: extract_sub_goals(decomposition_text),
      goal: goal,
      depth: depth,
      model: model,
      usage: Helpers.extract_usage(response)
    }
  end

  defp extract_sub_goals(text) do
    # Extract sub-goals in format like "1.1. [Sub-goal]"
    Regex.scan(~r/^\d+\.\d+\.\s+(.+?)$/m, text)
    |> Enum.map(fn [_, sub_goal] -> String.trim(sub_goal) end)
    |> Enum.filter(fn s -> String.length(s) > 0 end)
  end

  defp apply_context_defaults(params, context) when is_map(params) do
    context = normalize_context(context)
    provided = provided_params(context)

    model_default =
      first_present([
        context[:default_model],
        context[:model],
        plugin_default(context, :default_model)
      ])

    max_depth_default =
      first_present([
        context[:default_max_depth],
        plugin_default(context, :default_max_depth)
      ])

    max_tokens_default =
      first_present([
        context[:default_max_tokens],
        plugin_default(context, :default_max_tokens)
      ])

    temperature_default =
      first_present([
        context[:default_temperature],
        plugin_default(context, :default_temperature)
      ])

    params
    |> put_default_param(:model, model_default, provided)
    |> put_default_param(:max_depth, max_depth_default, provided)
    |> put_default_param(:max_tokens, max_tokens_default, provided)
    |> put_default_param(:temperature, temperature_default, provided)
  end

  defp apply_context_defaults(params, _context), do: params

  defp put_default_param(params, _key, nil, _provided), do: params

  defp put_default_param(params, key, default, :unknown) do
    if Map.get(params, key) in [nil, ""] do
      Map.put(params, key, default)
    else
      params
    end
  end

  defp put_default_param(params, key, default, provided) do
    if provided_param?(provided, key) do
      params
    else
      Map.put(params, key, default)
    end
  end

  defp provided_params(%{provided_params: provided}) when is_list(provided), do: provided
  defp provided_params(_), do: :unknown

  defp provided_param?(provided, key) when is_list(provided) do
    key_str = Atom.to_string(key)
    Enum.any?(provided, fn k -> k == key or k == key_str end)
  end

  defp plugin_default(context, key) do
    first_present([
      get_in(context, [:plugin_state, :planning, key]),
      get_in(context, [:state, :planning, key]),
      get_in(context, [:agent, :state, :planning, key])
    ])
  end

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
  defp normalize_context(context) when is_map(context), do: context
  defp normalize_context(_), do: %{}
end
