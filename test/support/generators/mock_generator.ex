defmodule Jido.AI.Accuracy.TestSupport.MockGenerator do
  @moduledoc """
  Mock generator for testing accuracy modules.

  Implements the Generator behavior without making actual LLM calls.
  Supports configurable candidates, failures, and delays.
  """

  @behaviour Jido.AI.Accuracy.Generator

  alias Jido.AI.Accuracy.{Candidate, Generator}

  @type t :: %__MODULE__{
          candidates: list(Candidate.t()),
          should_fail: boolean(),
          failure_reason: term(),
          delay_ms: non_neg_integer(),
          call_count: non_neg_integer()
        }

  defstruct [
    :candidates,
    :should_fail,
    :failure_reason,
    :delay_ms,
    :call_count
  ]

  @doc """
  Creates a new mock generator with options.

  ## Options

  - `:candidates` - List of candidates to return
  - `:should_fail` - Whether generate_candidates should fail
  - `:failure_reason` - Reason for failure
  - `:delay_ms` - Delay before returning (for testing timeouts)
  - `:num_candidates` - Number of generic candidates to create

  ## Examples

      # Create generator with specific candidates
      MockGenerator.new(candidates: [
        Candidate.new!(content: "42"),
        Candidate.new!(content: "42")
      ])

      # Create generator that returns N generic candidates
      MockGenerator.new(num_candidates: 3)

      # Create generator that simulates failure
      MockGenerator.new(should_fail: true, failure_reason: :api_error)
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    num_candidates = Keyword.get(opts, :num_candidates, 0)

    candidates =
      case Keyword.get(opts, :candidates) do
        nil when num_candidates > 0 ->
          Enum.map(1..num_candidates, fn i ->
            Candidate.new!(%{
              content: "Candidate #{i}",
              model: "mock-model",
              tokens_used: 10,
              metadata: %{index: i}
            })
          end)

        list when is_list(list) ->
          list

        _ ->
          []
      end

    %__MODULE__{
      candidates: candidates,
      should_fail: Keyword.get(opts, :should_fail, false),
      failure_reason: Keyword.get(opts, :failure_reason, :mock_failure),
      delay_ms: Keyword.get(opts, :delay_ms, 0),
      call_count: 0
    }
  end

  @doc """
  Returns the number of times the generator was called.
  """
  @spec call_count(t()) :: non_neg_integer()
  def call_count(%__MODULE__{call_count: count}), do: count

  @doc """
  Resets the call count.
  """
  @spec reset_call_count(t()) :: t()
  def reset_call_count(%__MODULE__{} = gen), do: %{gen | call_count: 0}

  # Generator behaviour callbacks

  @impl Generator
  def generate_candidates(%__MODULE__{} = gen, _prompt, _opts \\ []) do
    # Increment call count
    gen = %{gen | call_count: gen.call_count + 1}

    # Simulate delay if configured
    if gen.delay_ms > 0 do
      Process.sleep(gen.delay_ms)
    end

    # Return success or failure
    if gen.should_fail do
      {:error, gen.failure_reason}
    else
      {:ok, gen.candidates}
    end
  end

  @impl Generator
  def generate_candidates_async(%__MODULE__{} = gen, prompt, opts \\ []) do
    Task.async(fn -> generate_candidates(gen, prompt, opts) end)
  end

  @impl Generator
  def generate_with_reasoning(%__MODULE__{} = gen, prompt, opts \\ []) do
    case generate_candidates(gen, prompt, opts) do
      {:ok, candidates} ->
        # Add reasoning field to each candidate
        reasoned_candidates =
          Enum.map(candidates, fn candidate ->
            %{candidate | reasoning: "Mock reasoning for: #{prompt}"}
          end)

        {:ok, reasoned_candidates}

      {:error, _reason} = error ->
        error
    end
  end
end
