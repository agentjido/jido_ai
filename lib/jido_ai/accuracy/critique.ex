defmodule Jido.AI.Accuracy.Critique do
  @moduledoc """
  Behavior for critique generation.

  Critiquers analyze candidate responses to identify issues and suggest improvements.
  This behavior defines the interface for all critique implementations.

  ## Critique Patterns

  There are several patterns for generating critiques:

  1. **LLM-based critique** - Uses an LLM to analyze and provide feedback
  2. **Tool-based critique** - Executes tools to verify correctness
  3. **Rule-based critique** - Applies deterministic rules
  4. **Hybrid critique** - Combines multiple approaches

  ## Implementing the Behavior

  To implement the Critique behavior:

      defmodule MyCritiquer do
        @behaviour Jido.AI.Accuracy.Critique

        @impl true
        def critique(candidate, context) do
          # Analyze the candidate
          issues = analyze(candidate)
          suggestions = generate_suggestions(candidate, issues)

          {:ok, CritiqueResult.new!(%{
            issues: issues,
            suggestions: suggestions,
            severity: calculate_severity(issues)
          })}
        end
      end

  ## Context

  The context map may contain:
  - `:prompt` - Original prompt/question
  - `:domain` - Domain for specialized critique (e.g., :math, :code)
  - `:timeout` - Timeout in milliseconds
  - `:model` - Model to use for LLM-based critique
  - Custom keys for specific critiquer implementations

  ## Examples

      # LLM-based critique
      {:ok, critique} = LLMCritiquer.critique(candidate, %{
        prompt: "What is 15 * 23?",
        domain: :math
      })

      # Tool-based critique
      {:ok, critique} = ToolCritiquer.critique(candidate, %{
        tools: [:linter, :type_checker]
      })

  """

  alias Jido.AI.Accuracy.{Candidate, CritiqueResult}

  @type context :: map()
  @type critique_result :: {:ok, CritiqueResult.t()} | {:error, term()}

  @doc """
  Generate a critique for the given candidate (struct-based implementation).

  For struct-based critiquers that need to access their own configuration.

  ## Parameters

  - `critiquer` - The critiquer struct (self)
  - `candidate` - The candidate to critique
  - `context` - Additional context for the critique

  ## Returns

  - `{:ok, CritiqueResult.t()}` on success
  - `{:error, reason}` on failure

  """
  @callback critique(struct(), Candidate.t(), context()) :: critique_result()

  @doc """
  Generate critiques for multiple candidates.

  This callback is optional. If not implemented, the default
  implementation calls `critique/2` for each candidate.

  ## Parameters

  - `candidates` - List of candidates to critique
  - `context` - Additional context for the critique

  ## Returns

  - `{:ok, [CritiqueResult.t()]}` on success
  - `{:error, reason}` on failure

  """
  @callback critique_batch([Candidate.t()], context()) :: critique_result()

  @optional_callbacks [critique_batch: 2]

  @doc """
  Default implementation for batch critique.

  Calls `critique/3` for each candidate sequentially.

  """
  @spec critique_batch([Candidate.t()], context(), module()) :: critique_result()
  def critique_batch(candidates, context, critiquer) when is_list(candidates) do
    results =
      Enum.map(candidates, fn candidate ->
        critiquer.critique(candidate, context)
      end)

    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(errors) do
      {:ok,
       Enum.map(results, fn
         {:ok, critique} -> critique
         _ -> nil
       end)}
    else
      {:error, :batch_critique_failed}
    end
  end

  @doc """
  Checks if the given module is a critiquer.

  A module is considered a critiquer if it exports `critique/3`
  (self, candidate, context) for struct-based implementations.

  Note: Module-level `critique/2` implementations are not supported
  by the current behavior.

  """
  @spec critiquer?(term()) :: boolean()
  def critiquer?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :critique, 3)
  end

  def critiquer?(_), do: false

  @doc """
  Gets the critique behavior.

  """
  @spec behaviour() :: module()
  def behaviour, do: __MODULE__
end
