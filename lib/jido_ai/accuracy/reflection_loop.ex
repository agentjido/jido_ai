defmodule Jido.AI.Accuracy.ReflectionLoop do
  @moduledoc """
  Reflection loop orchestrator for iterative refinement through critique-revise cycles.

  The reflection loop implements the self-reflection pattern where a response is
  iteratively improved through multiple critique and revision cycles. Each iteration:

  1. Critiques the current candidate for issues
  2. Revises the candidate based on critique feedback
  3. Checks if convergence criteria are met
  4. Either continues or returns the best candidate

  ## Configuration

  - `:max_iterations` - Maximum refinement iterations (default: 3)
  - `:critiquer` - Critiquer module to use (required)
  - `:reviser` - Reviser module to use (required)
  - `:generator` - Optional generator for initial response
  - `:convergence_threshold` - Score improvement threshold (default: 0.1)
  - `:memory` - Optional ReflexionMemory for cross-episode learning

  ## Convergence Criteria

  The loop stops when:
  1. No new issues are found (critique severity plateaus)
  2. Score improvement is below threshold
  3. Max iterations reached (safety limit)

  ## Usage

      # Create loop with critiquer and reviser
      loop = ReflectionLoop.new!(%{
        critiquer: LLMCritiquer,
        reviser: LLMReviser,
        max_iterations: 3
      })

      # Run with initial candidate
      {:ok, result} = ReflectionLoop.run(loop, "What is 15 * 23?", %{
        initial_candidate: candidate,
        model: "anthropic:claude-haiku-4-5"
      })

      # Result contains history and best candidate
      result.best_candidate  # => The improved candidate
      result.iterations     # => List of iteration steps
      result.converged      # => Whether convergence was achieved

  ## With ReflexionMemory

      # Create with memory for cross-episode learning
      memory = ReflexionMemory.new!(%{
        max_entries: 1000
      })

      loop = ReflectionLoop.new!(%{
        critiquer: LLMCritiquer,
        reviser: LLMReviser,
        memory: memory
      })

      # Subsequent runs benefit from past critiques
      {:ok, result} = ReflectionLoop.run(loop, prompt, context)

  """

  alias Jido.AI.Accuracy.{Candidate, CritiqueResult, Critique, Revision, ReflexionMemory}

  @type t :: %__MODULE__{
          max_iterations: pos_integer(),
          critiquer: module(),
          reviser: module(),
          generator: module() | nil,
          convergence_threshold: float(),
          memory: {:ok, ReflexionMemory.t()} | nil
        }

  defstruct [
    :critiquer,
    :reviser,
    :generator,
    max_iterations: 3,
    convergence_threshold: 0.1,
    memory: nil
  ]

  @type iteration_step :: %{
          iteration: non_neg_integer(),
          candidate: Candidate.t(),
          critique: CritiqueResult.t() | nil,
          score: number() | nil
        }

  @type result :: %{
          best_candidate: Candidate.t(),
          iterations: [iteration_step()],
          converged: boolean(),
          reason: atom()
        }

  @doc """
  Creates a new reflection loop from the given attributes.

  ## Options

  - `:critiquer` - Critiquer module (required)
  - `:reviser` - Reviser module (required)
  - `:generator` - Optional generator for initial response
  - `:max_iterations` - Maximum iterations (default: 3)
  - `:convergence_threshold` - Score delta threshold (default: 0.1)
  - `:memory` - Optional ReflexionMemory struct

  ## Returns

  `{:ok, loop}` on success, `{:error, reason}` on validation failure.

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) or is_map(opts) do
    critiquer = get_opt_value(opts, :critiquer)
    reviser = get_opt_value(opts, :reviser)

    with :ok <- validate_critiquer(critiquer),
         :ok <- validate_reviser(reviser),
         :ok <- validate_max_iterations(get_opt_value(opts, :max_iterations, 3)),
         :ok <- validate_convergence_threshold(get_opt_value(opts, :convergence_threshold, 0.1)) do
      loop = %__MODULE__{
        critiquer: critiquer,
        reviser: reviser,
        generator: get_opt_value(opts, :generator),
        max_iterations: get_opt_value(opts, :max_iterations, 3),
        convergence_threshold: get_opt_value(opts, :convergence_threshold, 0.1),
        memory: get_opt_value(opts, :memory)
      }

      {:ok, loop}
    end
  end

  @doc """
  Creates a new reflection loop, raising on error.

  """
  @spec new!(keyword() | map()) :: t()
  def new!(opts) when is_list(opts) or is_map(opts) do
    case new(opts) do
      {:ok, loop} -> loop
      {:error, reason} -> raise ArgumentError, "Invalid ReflectionLoop: #{inspect(reason)}"
    end
  end

  @doc """
  Runs the reflection loop with the given prompt and context.

  ## Parameters

  - `loop` - The reflection loop configuration
  - `prompt` - The original prompt/question
  - `context` - Additional context including:
    - `:initial_candidate` - Starting candidate (optional, will generate if nil)
    - `:model` - Model for LLM operations
    - Other context passed to critiquer/reviser

  ## Returns

  `{:ok, result}` where result is a map with:
  - `:best_candidate` - The best candidate across iterations
  - `:iterations` - List of iteration steps
  - `:converged` - Whether convergence was achieved
  - `:reason` - Reason for stopping (:converged, :max_iterations, :error)

  """
  @spec run(t(), String.t(), map()) :: {:ok, result()} | {:error, term()}
  def run(%__MODULE__{} = loop, prompt, context) when is_binary(prompt) do
    _initial = Map.get(context, :initial_candidate)

    with {:ok, starting_candidate} <- get_or_generate_initial(loop, prompt, context) do
      # Retrieve similar critiques from memory if available
      context_with_memory = maybe_add_memory_context(loop, prompt, context)

      current_candidate = starting_candidate

      # Run iterations
      {result, _} =
        Stream.iterate(0, &(&1 + 1))
        |> Enum.reduce_while({%{iterations: [], best_candidate: current_candidate}, current_candidate}, fn
          iteration_num, {state, candidate} ->
            if iteration_num >= loop.max_iterations do
              # Max iterations reached
              final_result = finalize_result(state, loop, :max_iterations)
              {:halt, {final_result, candidate}}
            else
              case run_iteration(loop, prompt, candidate, iteration_num, context_with_memory) do
                {:ok, %{candidate: revised_candidate, critique: critique, converged: converged}} ->
                  new_step = %{
                    iteration: iteration_num,
                    candidate: revised_candidate,
                    critique: critique,
                    score: critique.severity
                  }

                  updated_state = %{
                    iterations: state.iterations ++ [new_step],
                    best_candidate: select_best(state.best_candidate, revised_candidate)
                  }

                  if converged do
                    final_result = finalize_result(updated_state, loop, :converged)
                    {:halt, {final_result, revised_candidate}}
                  else
                    {:cont, {updated_state, revised_candidate}}
                  end

                {:error, _reason} ->
                  final_result = finalize_result(state, loop, :error)
                  {:halt, {final_result, candidate}}
              end
            end
        end)

      # Store in memory if available
      _ = maybe_store_in_memory(loop, prompt, result)

      {:ok, result}
    end
  end

  @doc """
  Runs a single critique-revise iteration.

  ## Parameters

  - `loop` - The reflection loop configuration
  - `prompt` - The original prompt
  - `candidate` - Current candidate to improve
  - `iteration` - Current iteration number
  - `context` - Additional context

  ## Returns

  `{:ok, %{candidate: revised, critique: critique, converged: boolean}}`

  """
  @spec run_iteration(t(), String.t(), Candidate.t(), non_neg_integer(), map()) ::
          {:ok, %{candidate: Candidate.t(), critique: CritiqueResult.t(), converged: boolean()}}
          | {:error, term()}
  def run_iteration(%__MODULE__{} = loop, _prompt, candidate, iteration, context) do
    critiquer = loop.critiquer
    reviser = loop.reviser

    # Add iteration number to context
    context_with_iter = Map.put(context, :iteration, iteration)

    # Critique the current candidate
    critique_result =
      cond do
        function_exported?(critiquer, :critique, 3) ->
          critiquer.critique(critiquer, candidate, context_with_iter)

        function_exported?(critiquer, :critique, 2) ->
          critiquer.critique(candidate, context_with_iter)

        true ->
          {:error, :invalid_critiquer}
      end

    with {:ok, critique} <- critique_result,
         {:ok, revised} <- revise_candidate(reviser, candidate, critique, context_with_iter) do
      # Check convergence
      converged = check_convergence(loop, critique, candidate, revised)

      {:ok, %{candidate: revised, critique: critique, converged: converged}}
    end
  end

  @doc """
  Checks if the loop has converged based on critique and revision.

  Convergence occurs when:
  1. Critique severity is low (no significant issues)
  2. Score improvement is below threshold
  3. Content hasn't changed significantly

  """
  @spec check_convergence(t(), CritiqueResult.t(), Candidate.t(), Candidate.t()) :: boolean()
  def check_convergence(%__MODULE__{} = loop, %CritiqueResult{} = critique, original, revised) do
    # Check 1: Low severity (no significant issues)
    low_severity = critique.severity < 0.3

    # Check 2: Minimal content change
    minimal_change = minimal_content_change?(original.content, revised.content)

    # Check 3: Score plateau (if scores available)
    score_plateau =
      cond do
        is_number(original.score) and is_number(revised.score) ->
          abs(original.score - revised.score) < loop.convergence_threshold

        true ->
          false
      end

    # Converged if any condition is met
    low_severity or minimal_change or score_plateau
  end

  @doc """
  Calculates the improvement score between two candidates.

  Uses critique severity or candidate scores if available.

  """
  @spec improvement_score(Candidate.t(), Candidate.t(), CritiqueResult.t() | nil) :: float()
  def improvement_score(%Candidate{} = _original, %Candidate{} = _revised, %CritiqueResult{} = critique) do
    # Lower severity = better, so improvement = 1 - severity
    1.0 - critique.severity
  end

  def improvement_score(%Candidate{score: original_score}, %Candidate{score: revised_score}, nil)
      when is_number(original_score) and is_number(revised_score) do
    revised_score - original_score
  end

  def improvement_score(_, _, _), do: 0.0

  # Private functions

  # Helper function to get options from keyword list or map
  defp get_opt_value(opts, key) when is_list(opts) do
    Keyword.get(opts, key)
  end

  defp get_opt_value(opts, key) when is_map(opts) do
    Map.get(opts, key)
  end

  defp get_opt_value(opts, key, default) when is_list(opts) do
    Keyword.get(opts, key, default)
  end

  defp get_opt_value(opts, key, default) when is_map(opts) do
    Map.get(opts, key, default)
  end

  defp validate_critiquer(nil), do: {:error, :critiquer_required}
  defp validate_critiquer(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and
         (function_exported?(module, :critique, 2) or function_exported?(module, :critique, 3)) do
      :ok
    else
      {:error, :invalid_critiquer}
    end
  end

  defp validate_critiquer(_), do: {:error, :invalid_critiquer}

  defp validate_reviser(nil), do: {:error, :reviser_required}
  defp validate_reviser(module) when is_atom(module) do
    if Code.ensure_loaded?(module) and
         (function_exported?(module, :revise, 3) or function_exported?(module, :revise, 4)) do
      :ok
    else
      {:error, :invalid_reviser}
    end
  end

  defp validate_reviser(_), do: {:error, :invalid_reviser}

  defp validate_max_iterations(n) when is_integer(n) and n >= 1 and n <= 10, do: :ok
  defp validate_max_iterations(_), do: {:error, :invalid_max_iterations}

  defp validate_convergence_threshold(t) when is_number(t) and t >= 0.0 and t <= 1.0, do: :ok
  defp validate_convergence_threshold(_), do: {:error, :invalid_convergence_threshold}

  defp get_or_generate_initial(%__MODULE__{generator: nil}, _prompt, context) do
    case Map.get(context, :initial_candidate) do
      nil -> {:error, :no_initial_candidate}
      %Candidate{} = candidate -> {:ok, candidate}
    end
  end

  defp get_or_generate_initial(%__MODULE__{generator: generator}, prompt, context) do
    case Map.get(context, :initial_candidate) do
      nil ->
        # Generate initial candidate
        generator_opts = Map.take(context, [:model, :temperature, :timeout])

        case generator.generate_candidates(generator, prompt, generator_opts) do
          {:ok, []} -> {:error, :no_candidates_generated}
          {:ok, [first | _]} -> {:ok, first}
          {:ok, single} when not is_list(single) -> {:ok, single}
          error -> error
        end

      %Candidate{} = candidate ->
        {:ok, candidate}
    end
  end

  defp revise_candidate(reviser, candidate, critique, context) do
    cond do
      function_exported?(reviser, :revise, 4) ->
        reviser.revise(reviser, candidate, critique, context)

      function_exported?(reviser, :revise, 3) ->
        reviser.revise(candidate, critique, context)

      true ->
        {:error, :invalid_reviser}
    end
  end

  defp minimal_content_change?(nil, nil), do: true
  defp minimal_content_change?(original, revised) when is_binary(original) and is_binary(revised) do
    # Calculate edit distance ratio
    original_len = String.length(original)
    revised_len = String.length(revised)

    if original_len == 0 and revised_len == 0 do
      true
    else
      max_len = max(original_len, revised_len)
      diff_len = abs(original_len - revised_len)

      # Consider minimal if less than 10% change
      diff_len / max_len < 0.1
    end
  end

  defp minimal_content_change?(_, _), do: false

  defp select_best(%Candidate{score: score1}, %Candidate{score: score2} = c2)
       when is_number(score1) and is_number(score2) do
    if score2 >= score1, do: c2, else: c2
  end

  defp select_best(%Candidate{}, %Candidate{} = c2), do: c2

  defp finalize_result(state, _loop, reason) do
    %{
      best_candidate: state.best_candidate,
      iterations: state.iterations,
      converged: reason == :converged,
      reason: reason,
      total_iterations: length(state.iterations)
    }
  end

  defp maybe_add_memory_context(%__MODULE__{memory: nil}, _prompt, context), do: context

  defp maybe_add_memory_context(%__MODULE__{memory: {:ok, memory}}, prompt, context) do
    case ReflexionMemory.retrieve_similar(memory, prompt, max_results: 3) do
      {:ok, []} -> context
      {:ok, memories} -> Map.put(context, :past_mistakes, memories)
      _ -> context
    end
  end

  defp maybe_store_in_memory(%__MODULE__{memory: nil}, _prompt, _result), do: :ok

  defp maybe_store_in_memory(%__MODULE__{memory: {:ok, memory}}, prompt, result) do
    # Store if there were iterations with critiques
    critiques =
      result.iterations
      |> Enum.filter(fn i -> i.critique != nil end)
      |> Enum.map(fn i -> i.critique end)

    if Enum.any?(critiques, fn c -> c.severity > 0.3 end) do
      # Store high-severity critiques
      Enum.each(critiques, fn critique ->
        if critique.severity > 0.3 do
          :ok = ReflexionMemory.store(memory, %{
            prompt: prompt,
            mistake: Enum.join(critique.issues || [], "; "),
            correction: Enum.join(critique.suggestions || [], "; "),
            severity: critique.severity,
            timestamp: DateTime.utc_now()
          })
        end
      end)
    else
      :ok
    end
  end
end
