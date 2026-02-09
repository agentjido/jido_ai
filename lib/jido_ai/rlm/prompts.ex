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
  def system_prompt(%{tools: _tools}) do
    """
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
  end

  @spec next_step_prompt(map()) :: %{role: :user, content: String.t()}
  def next_step_prompt(%{query: query, iteration: 1, workspace_summary: _summary}) do
    %{
      role: :user,
      content: "You have not explored the context yet. Start by examining its structure.\n\nQuery: \"#{query}\""
    }
  end

  def next_step_prompt(%{query: query, iteration: _iteration, workspace_summary: summary}) do
    %{
      role: :user,
      content: """
      Continue exploring to answer the query: "#{query}"

      ## Exploration Progress
      #{summary}

      Decide your next action: search, delegate to sub-LLM, or provide your final answer.\
      """
    }
  end
end
