defmodule Jido.AI.RLM.Prompts do
  @moduledoc """
  Prompt builders for the RLM (Recursive Large Model) strategy.

  Provides structured prompt construction for guiding an LLM through
  iterative exploration of a large context. The LLM acts as a data analyst,
  using tools to chunk, search, and delegate sub-queries rather than
  attempting to consume the entire context at once.

  ## Usage

      config = %{tools: [MyApp.SearchTool, MyApp.ChunkTool]}
      system = Prompts.system_prompt(config)

      step = Prompts.next_step_prompt(%{
        query: "Find revenue trends",
        iteration: 1,
        workspace_summary: ""
      })
  """

  @spec system_prompt(map()) :: String.t()
  def system_prompt(config) do
    max_depth = Map.get(config, :max_depth, 0)

    base = """
    You are a data analyst exploring a large context that cannot be consumed all at once.

    ## Methodology

    1. **Check stats** — Examine the structure, size, and metadata of the context before diving in.
    2. **Chunk** — Break the context into manageable pieces for focused analysis.
    3. **Search / Delegate** — Use search tools to locate relevant sections, or delegate sub-queries to specialized sub-LLMs when the question is decomposable.
    4. **Record hypotheses** — As you explore, record intermediate hypotheses and supporting evidence in your workspace.
    5. **Answer when confident** — Only provide a final answer once you have gathered sufficient evidence and cross-checked your findings.

    ## Guidelines

    - Never attempt to read the entire context at once. Always work in focused chunks.
    - Use subquery batches to parallelize exploration when multiple independent questions arise.
    - Record your reasoning at each step so that progress is preserved across iterations.
    - Prefer precision over recall — it is better to be confident in a partial answer than to guess at a complete one.
    """

    if max_depth > 0 do
      base <>
        """

        ## Tool Selection Guide

        - **`llm_subquery_batch`** — Single-step map-reduce. Ask a simple question of each chunk (e.g., "does this chunk contain X?"). Fast and cheap.
        - **`rlm_spawn_agent`** — Multi-step deep exploration. Spawns a child agent that can chunk, search, and reason within a context subset. Use when a chunk requires complex analysis (e.g., "analyze this section and extract all Y with supporting evidence").
        """
    else
      base
    end
  end

  @spec next_step_prompt(map()) :: %{role: :user, content: String.t()}
  def next_step_prompt(%{query: query, iteration: 1} = params) do
    depth_line = depth_line(params)

    %{
      role: :user,
      content:
        "You have not explored the context yet. Start by examining its structure.\n" <>
          depth_line <>
          "\nQuery: \"#{query}\""
    }
  end

  def next_step_prompt(%{query: query, iteration: _iteration, workspace_summary: summary} = params) do
    depth_line = depth_line(params)

    %{
      role: :user,
      content: """
      Continue exploring to answer the query: "#{query}"
      #{depth_line}
      ## Exploration Progress
      #{summary}

      Decide your next action: search, delegate to sub-LLM, or provide your final answer.\
      """
    }
  end

  defp depth_line(params) do
    current_depth = Map.get(params, :current_depth, 0)
    max_depth = Map.get(params, :max_depth, 0)

    cond do
      max_depth <= 0 ->
        ""

      current_depth >= max_depth ->
        "\nDepth: #{current_depth}/#{max_depth}.\nYou are at maximum depth — use batch queries, not agent spawning.\n"

      true ->
        "\nDepth: #{current_depth}/#{max_depth}.\n"
    end
  end
end
