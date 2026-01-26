defmodule Jido.AI.Accuracy.SearchController do
  @moduledoc """
  Behavior for search algorithms in the accuracy improvement system.

  Search controllers systematically explore the solution space using verifiers
  to guide exploration toward better candidates. This enables test-time compute
  scaling through intelligent search rather than random sampling.

  ## Required Callbacks

  Every search controller must implement:

  - `search/4` - Execute search and return best candidate

  ## Optional Callbacks

  - `search_stream/4` - Stream search results for monitoring

  ## Usage

  Implement this behavior to create custom search algorithms:

      defmodule MyApp.Search.CustomSearch do
        @behaviour Jido.AI.Accuracy.SearchController

        @impl true
        def search(prompt, generator, verifier, opts) do
          # Implement search algorithm
          {:ok, best_candidate}
        end
      end

  ## Search Algorithms

  ### Beam Search

  Maintains top-K candidates at each step, expanding and verifying:

      {:ok, best} = BeamSearch.search("What is 15 * 23?", generator, verifier,
        beam_width: 5,
        depth: 3
      )

  ### MCTS (Monte Carlo Tree Search)

  Explores reasoning tree with UCB1 selection and backpropagation:

      {:ok, best} = MCTS.search("Solve: x^2 + 5x + 6 = 0", generator, verifier,
        simulations: 100,
        exploration_constant: 1.414
      )

  ### Diverse Decoding

  Generates diverse candidates using MMR (Maximal Marginal Relevance):

      {:ok, best} = DiverseDecoding.search("Explain quantum entanglement", generator, verifier,
        num_candidates: 10,
        diversity_threshold: 0.7
      )

  ## Search Options

  Common options across all search algorithms:

  | Option | Type | Default | Description |
  |--------|------|---------|-------------|
  | `:max_iterations` | `pos_integer/0` | `10` | Maximum search iterations |
  | `:timeout` | `pos_integer/0` | `30000` | Per-search timeout in ms |
  | `:beam_width` | `pos_integer/0` | `5` | Beam width (BeamSearch) |
  | `:depth` | `pos_integer/0` | `3` | Search depth (BeamSearch) |
  | `:simulations` | `pos_integer/0` | `100` | MCTS simulations |
  | `:exploration_constant` | `float/0` | `1.414` | UCB1 exploration (MCTS) |
  | `:num_candidates` | `pos_integer/0` | `10` | Candidates to generate |
  | `:diversity_threshold` | `float/0` | `0.7` | Minimum diversity |
  | `:temperature_range` | `{float, float}` | `{0.0, 1.0}` | Temperature range |

  ## Return Values

  The `search/4` callback should return:

  - `{:ok, Candidate.t()}` - Successfully found best candidate
  - `{:error, reason}` - Search failed

  ## Context

  Search controllers use the generator to create candidates and the verifier
  to score them. The verifier guides exploration by scoring partial or
  complete candidates.

  ## Examples

      # Use beam search to find best answer
      {:ok, best} = BeamSearch.search(
        "What is the capital of Australia?",
        LLMGenerator,
        DeterministicVerifier,
        beam_width: 5,
        depth: 2
      )

      # Use MCTS for complex reasoning
      {:ok, best} = MCTS.search(
        "Prove that sqrt(2) is irrational",
        LLMGenerator,
        LLMPrm,
        simulations: 200
      )

      # Use diverse decoding for variety
      {:ok, best} = DiverseDecoding.search(
        "Write a poem about AI",
        LLMGenerator,
        LLMOutcomeVerifier,
        num_candidates: 15,
        diversity_threshold: 0.6
      )

  ## Performance Considerations

  - **Beam Search**: O(depth * beam_width * branching_factor * verification_time)
  - **MCTS**: O(simulations * max_depth * (selection + simulation))
  - **Diverse Decoding**: O(num_candidates^2 * similarity_time)

  Use beam search for faster results, MCTS for deeper reasoning, and
  diverse decoding when variety is important.

  ## See Also

  - `Jido.AI.Accuracy.Search.BeamSearch` - Beam search implementation
  - `Jido.AI.Accuracy.Search.MCTS` - Monte Carlo Tree Search
  - `Jido.AI.Accuracy.Search.DiverseDecoding` - Diverse decoding
  - `Jido.AI.Accuracy.SearchState` - State tracking during search

  """

  alias Jido.AI.Accuracy.Candidate

  @type t :: module()
  @type generator :: module()
  @type verifier :: module()

  @type search_option ::
          {:max_iterations, pos_integer()}
          | {:timeout, pos_integer()}
          | {:beam_width, pos_integer()}
          | {:depth, pos_integer()}
          | {:branching_factor, pos_integer()}
          | {:simulations, pos_integer()}
          | {:exploration_constant, float()}
          | {:num_candidates, pos_integer()}
          | {:diversity_threshold, float()}
          | {:temperature_range, {float(), float()}}
          | {:lambda, float()}
          | {:max_depth, pos_integer()}
          | {:convergence_threshold, float()}
          | {:stagnation_count, pos_integer()}

  @type search_opts :: [search_option()]

  @type search_result :: {:ok, Candidate.t()} | {:error, term()}
  @type stream_result :: Enumerable.t({:intermediate, Candidate.t()} | {:final, Candidate.t()})

  @doc """
  Executes search algorithm to find best candidate.

  ## Parameters

  - `prompt` - The input prompt to search for
  - `generator` - Module implementing candidate generation
  - `verifier` - Module implementing candidate verification
  - `opts` - Search algorithm options

  ## Returns

  - `{:ok, candidate}` - Best candidate found
  - `{:error, reason}` - Search failed

  ## Examples

      iex> {:ok, best} = search_controller.search("What is 2+2?", generator, verifier, [])
      iex> best.content
      "4"

  """
  @callback search(prompt :: String.t(), generator :: generator(), verifier :: verifier(), opts :: search_opts()) ::
              search_result()

  @doc """
  Executes search with streaming intermediate results.

  This optional callback allows monitoring search progress by emitting
  intermediate candidates as the search explores the solution space.

  ## Parameters

  - `prompt` - The input prompt to search for
  - `generator` - Module implementing candidate generation
  - `verifier` - Module implementing candidate verification
  - `opts` - Search algorithm options

  ## Returns

  - Stream of `{:intermediate, candidate}` or `{:final, candidate}` tuples

  ## Examples

      stream = search_controller.search_stream("prompt", generator, verifier, [])
      Enum.each(stream, fn {_status, _candidate} ->
        # Process each result
        :ok
      end)

  """
  @callback search_stream(
              prompt :: String.t(),
              generator :: generator(),
              verifier :: verifier(),
              opts :: search_opts()
            ) :: stream_result()

  @optional_callbacks [search_stream: 4]

  @doc """
  Validates search options.

  ## Parameters

  - `opts` - Keyword list of search options
  - `valid_keys` - List of valid option keys

  ## Returns

  - `:ok` - Options are valid
  - `{:error, reason}` - Invalid options

  """
  @spec validate_opts(keyword(), [atom()]) :: :ok | {:error, term()}
  def validate_opts(opts, valid_keys) when is_list(opts) do
    invalid_keys =
      opts
      |> Keyword.keys()
      |> Enum.reject(fn key -> key in valid_keys end)

    if invalid_keys == [] do
      :ok
    else
      {:error, {:invalid_options, invalid_keys}}
    end
  end

  @doc """
  Extracts timeout from options with default.

  """
  @spec get_timeout(keyword(), pos_integer()) :: pos_integer()
  def get_timeout(opts, default \\ 30_000) do
    Keyword.get(opts, :timeout, default)
  end

  @doc """
  Checks if search has exceeded timeout.

  """
  @spec timeout_exceeded?(integer(), pos_integer()) :: boolean()
  def timeout_exceeded?(start_time, timeout_ms) do
    System.monotonic_time(:millisecond) - start_time > timeout_ms
  end
end
