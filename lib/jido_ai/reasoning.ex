defmodule Jido.AI.Reasoning do
  @moduledoc false
  alias Jido.AI.{Output, Profile}
  alias Jido.AI.Reasoning.{Linear, AlgorithmOfThoughts, TreeSearch, GraphSearch, Recursive}

  def react_prompt do
    """
    You are a helpful AI assistant using the ReAct (Reason-Act) pattern.
    When you need to perform an action, use the available tools.
    When you have enough information to answer, provide your final answer directly.
    Think step by step and explain your reasoning.
    """
  end

  def single_pass?(method), do: Linear.linear?(method) or method == :algorithm_of_thoughts
  def label(:chain_of_thought), do: :cot
  def label(:chain_of_draft), do: :cod
  def label(:tree_of_thoughts), do: :tot
  def label(:graph_of_thoughts), do: :got
  def label(:algorithm_of_thoughts), do: :aot
  def label(method), do: method

  def options(method, value) when is_list(value) do
    if Keyword.keyword?(value) and length(value) == length(Keyword.keys(value) |> Enum.uniq()),
      do: options(method, Map.new(value)),
      else: Profile.error("reasoning.options", "Expected unique method option keys")
  end

  def options(:adaptive, value), do: Jido.AI.Reasoning.Adaptive.Selection.options(value)
  def options(:trm, value), do: Recursive.options(value)
  def options(:tree_of_thoughts, value), do: TreeSearch.options(value)
  def options(:graph_of_thoughts, value), do: GraphSearch.options(value)
  def options(:algorithm_of_thoughts, value), do: AlgorithmOfThoughts.options(value)
  def options(_, value) when value == %{}, do: {:ok, %{}}
  def options(_, _), do: Profile.error("reasoning.options", "This method has no method options")

  # Upper bounds for public wrappers. Explicit shared controls always take precedence.
  def model_call_limit(:tree_of_thoughts, opts),
    do:
      min(
        2 * opts.max_nodes * (opts.max_tool_round_trips + 1) + 2 * opts.max_parse_retries,
        10_000
      )

  def model_call_limit(:graph_of_thoughts, opts), do: min(2 * opts.max_nodes, 10_000)
  def model_call_limit(:trm, opts), do: min(3 * opts.max_supervision_steps, 10_000)
  def model_call_limit(:react, _), do: 10
  def model_call_limit(_, _), do: 1

  def select(%{reasoning: %{method: :adaptive}} = profile, query),
    do: Jido.AI.Reasoning.Adaptive.Selection.select(profile, query)

  def select(profile, _query) do
    with {:ok, profile} <- Profile.resolve_controls(profile), do: {:ok, profile, nil}
  end

  def instructions(%{reasoning: %{method: :algorithm_of_thoughts}} = profile, output),
    do: AlgorithmOfThoughts.instructions(profile, output)

  def instructions(profile, output),
    do: [
      Linear.instructions(profile.reasoning.method, profile.instructions),
      Output.instructions(output)
    ]

  def query(%{reasoning: %{method: :algorithm_of_thoughts}}, query) when is_binary(query),
    do: AlgorithmOfThoughts.Machine.user_prompt(query)

  def query(%{reasoning: %{method: :algorithm_of_thoughts}}, query) when is_list(query),
    do: [ReqLLM.Message.ContentPart.text(AlgorithmOfThoughts.Machine.user_prompt("")) | query]

  def query(_, query), do: query

  def generation(%{reasoning: %{method: method}}, generation)
      when method in [:tree_of_thoughts, :graph_of_thoughts, :trm],
      do: Keyword.merge([temperature: 0.2, max_tokens: 1024], generation)

  def generation(%{reasoning: %{method: :algorithm_of_thoughts}}, generation),
    do: Keyword.merge([temperature: 0.0, max_tokens: 2048], generation)

  def generation(%{reasoning: %{method: :react}}, generation),
    do: Keyword.merge([temperature: 0.2, max_tokens: 4096], generation)

  def generation(_, generation), do: generation

  def provider_schema(%{reasoning: %{method: :trm}}, _), do: nil
  def provider_schema(%{reasoning: %{method: :tree_of_thoughts}}, _), do: nil
  def provider_schema(%{reasoning: %{method: :graph_of_thoughts}}, _), do: nil
  def provider_schema(%{reasoning: %{method: :algorithm_of_thoughts}}, _), do: nil
  def provider_schema(_, nil), do: nil
  def provider_schema(_, output), do: output.schema

  def prepare(%{profile: %{reasoning: %{method: :tree_of_thoughts}}} = state, query),
    do: TreeSearch.prepare(state, query)

  def prepare(%{profile: %{reasoning: %{method: :graph_of_thoughts}}} = state, query),
    do: GraphSearch.prepare(state, query)

  def prepare(%{profile: %{reasoning: %{method: :trm}}} = state, query),
    do: Recursive.prepare(state, query)

  def prepare(state, _query), do: {:ok, state}

  def advance(%{tree_search: _} = state), do: TreeSearch.advance(state)
  def advance(%{graph_search: _} = state), do: GraphSearch.advance(state)
  def advance(%{recursive: _} = state), do: Recursive.advance(state)
  def advance(state), do: {:done, state}

  def tool_round(%{tree_search: _} = state), do: TreeSearch.tool_round(state)
  def tool_round(%{graph_search: _}), do: {:error, {:unexpected_tool_calls, :graph_of_thoughts}}
  def tool_round(%{recursive: _}), do: {:error, {:unexpected_tool_calls, :trm}}
  def tool_round(state), do: {:ok, state}

  def tools_disabled?(%{repairs: n}) when n > 0, do: true
  def tools_disabled?(%{tree_search: %{parser_repair?: true}}), do: true
  def tools_disabled?(%{graph_search: _}), do: true
  def tools_disabled?(%{recursive: _}), do: true

  def tools_disabled?(%{profile: %{reasoning: %{method: method}}})
      when method not in [:react, :tree_of_thoughts], do: true

  def tools_disabled?(_), do: false

  def tools(state), do: if(tools_disabled?(state), do: [], else: state.profile.tools)

  def event(state) do
    case state[:adaptive] do
      nil ->
        method_event(state)

      selection ->
        Map.merge(method_event(state), %{selected_method: selection.method, adaptive: selection})
    end
  end

  defp method_event(%{tree_search: _} = state), do: TreeSearch.event(state)
  defp method_event(%{graph_search: _} = state), do: GraphSearch.event(state)
  defp method_event(%{recursive: _} = state), do: Recursive.event(state)
  defp method_event(_), do: %{}

  @doc false
  def inspection(%{recursive: machine, usage: usage}),
    do: %{method: :trm, trm: Jido.AI.Reasoning.TRM.Machine.to_map(%{machine | usage: usage})}

  def inspection(_), do: nil

  def parse(state, value) do
    case method_parse(state, value) do
      {:ok, answer, meta} when is_map_key(state, :adaptive) ->
        {:ok, answer, Map.put(meta, :adaptive, state.adaptive)}

      result ->
        result
    end
  end

  defp method_parse(%{recursive: _} = state, value), do: Recursive.parse(state, value)
  defp method_parse(%{tree_search: _} = state, value), do: TreeSearch.parse(state, value)
  defp method_parse(%{graph_search: _} = state, value), do: GraphSearch.parse(state, value)

  defp method_parse(%{profile: %{reasoning: %{method: :algorithm_of_thoughts}}} = state, value),
    do: AlgorithmOfThoughts.parse(state, value)

  defp method_parse(state, value) do
    parsed =
      if state.output,
        do: Output.parse(state.output, value),
        else:
          {:ok,
           if(is_binary(value),
             do: value,
             else: value |> Jido.AI.Turn.from_response() |> Jido.AI.Turn.result()
           )}

    with {:ok, answer} <- parsed do
      {projected, meta} = Linear.project(state.profile.reasoning.method, answer, raw(value))
      {:ok, if(state.output, do: answer, else: projected), meta}
    end
  end

  def failure(state, reason) do
    failure = method_failure(state, reason)

    case {state[:adaptive], failure} do
      {nil, _} ->
        failure

      {selection, {:failed, cause, details}} when is_map(details) ->
        {:failed, cause, Map.put(details, :adaptive, selection)}

      {selection, cause} ->
        {:failed, cause, %{adaptive: selection, usage: state.usage, diagnostics: %{cause: cause}}}
    end
  end

  defp method_failure(%{recursive: _} = state, reason), do: Recursive.failure(state, reason)
  defp method_failure(%{tree_search: _} = state, reason), do: TreeSearch.failure(state, reason)
  defp method_failure(%{graph_search: _} = state, reason), do: GraphSearch.failure(state, reason)

  defp method_failure(
         %{profile: %{reasoning: %{method: :algorithm_of_thoughts}}} = state,
         reason
       ),
       do: AlgorithmOfThoughts.failure(state, reason)

  defp method_failure(_, reason), do: reason

  def account_failure({:error, {:failed, reason, result}}, method, usage)
      when method in [
             :algorithm_of_thoughts,
             :tree_of_thoughts,
             :graph_of_thoughts,
             :trm,
             :adaptive
           ] and
             is_map(result) and
             is_map(usage),
      do: {:error, {:failed, reason, Map.put(result, :usage, usage)}}

  def account_failure(outcome, _, _), do: outcome

  def raw(%ReqLLM.Response{} = value), do: ReqLLM.Response.text(value)
  def raw(value) when is_binary(value), do: value
  def raw(value), do: inspect(value)
end
