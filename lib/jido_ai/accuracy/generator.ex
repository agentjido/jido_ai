defmodule Jido.AI.Accuracy.Generator do
  @moduledoc """
  Behavior for candidate generators in the accuracy improvement system.

  Generators produce multiple candidate responses from a single prompt,
  enabling self-consistency and other test-time compute scaling techniques.

  ## Required Callbacks

  Every generator must implement:

  - `generate_candidates/3` - Generate N candidates from a prompt
  - `generate_candidates_async/3` - Async version returning Task
  - `generate_with_reasoning/3` - Generate candidates with Chain-of-Thought

  ## Usage

  Implement this behavior to create custom generators:

      defmodule MyApp.Generators.Custom do
        @behaviour Jido.AI.Accuracy.Generator

        @impl true
        def generate_candidates(generator, prompt, opts \\\\ []) do
          # Generate N candidates
          {:ok, [%Candidate{content: "answer1"}, ...]}
        end

        @impl true
        def generate_candidates_async(generator, prompt, opts \\\\ []) do
          Task.async(fn -> generate_candidates(generator, prompt, opts) end)
        end

        @impl true
        def generate_with_reasoning(generator, prompt, opts \\\\ []) do
          # Generate with reasoning traces
          {:ok, [%Candidate{reasoning: "step1...", content: "answer"}, ...]}
        end
      end

  ## Options

  Common options across generators:

  - `:num_candidates` - Number of candidates to generate (default: 5)
  - `:model` - Model to use (default: from config)
  - `:temperature` - Sampling temperature (default: 0.7)
  - `:temperature_range` - Range for temperature variation `{min, max}`
  - `:timeout` - Per-candidate timeout in ms (default: 30_000)
  - `:max_concurrency` - Max parallel generations (default: 3)
  - `:system_prompt` - Optional system prompt

  ## See Also

  - `Jido.AI.Accuracy.Generators.LLMGenerator` - LLM-based implementation
  """

  alias Jido.AI.Accuracy.Candidate

  @type t :: module()
  @type opts :: keyword()

  @type generate_result :: {:ok, [Candidate.t()]} | {:error, term()}

  @doc """
  Generates multiple candidate responses from a single prompt.

  ## Parameters

  - `generator` - The generator struct
  - `prompt` - The input prompt to generate candidates from
  - `opts` - Generator options

  ## Returns

  - `{:ok, candidates}` - List of generated candidates
  - `{:error, reason}` - Generation failed

  ## Examples

      iex> LLMGenerator.generate_candidates(generator, "What is 2+2?", num_candidates: 3)
      {:ok, [%Candidate{content: "4"}, ...]}
  """
  @callback generate_candidates(generator :: term(), prompt :: String.t(), opts :: opts()) :: generate_result()

  @doc """
  Generates candidates asynchronously, returning a Task.

  The Task should resolve to the same result as `generate_candidates/3`.

  ## Parameters

  - `generator` - The generator struct
  - `prompt` - The input prompt to generate candidates from
  - `opts` - Generator options

  ## Returns

  A Task that resolves to `{:ok, candidates}` or `{:error, reason}`.

  ## Examples

      iex> task = LLMGenerator.generate_candidates_async(generator, "What is 2+2?", [])
      iex> Task.await(task)
      {:ok, [%Candidate{content: "4"}, ...]}
  """
  @callback generate_candidates_async(generator :: term(), prompt :: String.t(), opts :: opts()) :: Task.t()

  @doc """
  Generates candidates with Chain-of-Thought reasoning traces.

  This method should prompt the model to think step-by-step and
  store the reasoning trace separately from the final answer.

  ## Parameters

  - `generator` - The generator struct
  - `prompt` - The input prompt to generate candidates from
  - `opts` - Generator options

  ## Returns

  - `{:ok, candidates}` - List of candidates with reasoning field populated
  - `{:error, reason}` - Generation failed

  ## Examples

      iex> LLMGenerator.generate_with_reasoning(generator, "Solve: 15 * 23 + 7", [])
      {:ok, [
        %Candidate{
          reasoning: "Let me calculate step by step...",
          content: "The answer is 352"
        },
        ...
      ]}
  """
  @callback generate_with_reasoning(generator :: term(), prompt :: String.t(), opts :: opts()) :: generate_result()

  @optional_callbacks [
    generate_candidates_async: 3,
    generate_with_reasoning: 3
  ]
end
