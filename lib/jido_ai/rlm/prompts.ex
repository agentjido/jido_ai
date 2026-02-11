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
    orchestration_mode = Map.get(config, :orchestration_mode, :auto)

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
      base <> tool_selection_guide(orchestration_mode)
    else
      base
    end
  end

  defp tool_selection_guide(:lua_only) do
    """

    ## Tool Selection Guide

    - **`llm_subquery_batch`** — Single-step map-reduce. Ask a simple question of each chunk (e.g., "does this chunk contain X?"). Fast and cheap.
    - **`rlm_lua_plan`** — Required orchestration path. After chunking, write Lua that inspects chunk metadata and returns plan items `{chunk_ids = {...}, query = "..."}`.
    - Prefer `rlm_lua_plan` over ad-hoc fan-out. Keep plans bounded by `budget.max_plan_items` and `budget.max_total_chunks`.
    """
  end

  defp tool_selection_guide(:spawn_only) do
    """

    ## Tool Selection Guide

    - **`llm_subquery_batch`** — Single-step map-reduce. Ask a simple question of each chunk (e.g., "does this chunk contain X?"). Fast and cheap.
    - **`rlm_spawn_agent`** — Multi-step deep exploration. Spawns a child agent that can chunk, search, and reason within a context subset. Use when a chunk requires complex analysis (e.g., "analyze this section and extract all Y with supporting evidence"). Best for small, targeted fan-outs (2-5 chunks).
    """
  end

  defp tool_selection_guide(_mode) do
    """

    ## Tool Selection Guide

    - **`llm_subquery_batch`** — Single-step map-reduce. Ask a simple question of each chunk (e.g., "does this chunk contain X?"). Fast and cheap.
    - **`rlm_spawn_agent`** — Multi-step deep exploration. Spawns a child agent that can chunk, search, and reason within a context subset. Use when a chunk requires complex analysis (e.g., "analyze this section and extract all Y with supporting evidence"). Best for small, targeted fan-outs (2-5 chunks).
    - **`rlm_lua_plan`** — Code-driven orchestration. Write a Lua script that inspects the chunk index and returns a structured plan for which chunks to explore and what to ask. Use when you need to selectively filter or group chunks before spawning (e.g., filter by preview content, group related chunks, apply different queries to different regions). The script receives `chunks`, `query`, `workspace_summary`, and `budget` as globals. Return an array of `{chunk_ids = {...}, query = "..."}` items. Example:
      ```lua
      local plan = {}
      for i = 1, math.min(#chunks, budget.max_total_chunks) do
        plan[#plan+1] = { chunk_ids = {chunks[i].id}, query = query }
      end
      return plan
      ```
    """
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

  @spec synthesis_prompt(map()) :: %{role: :user, content: String.t()}
  def synthesis_prompt(opts) do
    errors_note =
      case opts[:errors] do
        n when is_integer(n) and n > 0 -> "\nNote: #{n} chunks failed to process.\n"
        _ -> ""
      end

    %{
      role: :user,
      content: """
      You are synthesizing results from #{opts[:chunk_count]} parallel analyses into a final answer.
      You have NO tools available. Do NOT attempt to call any tools or functions.
      All the information you need is provided below.

      ORIGINAL QUERY: #{opts[:original_query]}

      CHILD RESULTS:
      #{opts[:workspace_summary]}
      #{errors_note}
      Using ONLY the child results above, synthesize a single coherent answer to the original query.
      Be precise, cite specific data found by the children, and resolve any contradictions.
      Respond with the final answer directly — no tool calls, no further exploration.\
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
