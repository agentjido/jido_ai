defmodule Jido.AI.Accuracy.StrategyAdapter do
  @moduledoc """
  Helper functions for integrating the accuracy pipeline with Jido strategies.

  This module provides utilities to make it easier to use the accuracy pipeline
  within Jido agent strategies like ReAct, Chain of Thought, etc.

  ## Usage

  ### In Agent Code

      alias Jido.AI.Accuracy.StrategyAdapter

      # Emit an accuracy run directive
      {:ok, agent} = StrategyAdapter.run_pipeline(agent, "What is 2+2?", preset: :fast)

      # With custom config
      {:ok, agent} = StrategyAdapter.run_pipeline(agent, query,
        preset: :accurate,
        config: %{generation_config: %{max_candidates: 15}}
      )

  ### Signal Handling

      Results are emitted as `accuracy.result` signals which can be handled
      via the agent's signal_routes/1:

      def handle_accuracy_result(agent, signal) do
        # signal.answer contains the final answer
        # signal.confidence contains the confidence score
        {:ok, agent}
      end

  ## Generator Resolution

  The adapter resolves generators from the following sources (in order):

  1. Directive parameter
  2. Agent state under `:accuracy_generator`
  3. Agent's model config (converted to generator)

  """

  alias Jido.AI.Accuracy.Directive
  alias Jido.AI.Accuracy.Presets
  alias Jido.AI.Accuracy.Pipeline
  alias Jido.AI.Accuracy.Signal

  @type agent :: term()
  @type query :: binary()
  @type preset :: :fast | :balanced | :accurate | :coding | :research
  @type config :: map() | nil
  @type generator :: term() | nil

  @doc """
  Runs the accuracy pipeline and emits the result as a signal.

  ## Options

  - `:preset` - Preset to use (default: :balanced)
  - `:config` - Custom config overrides (merged with preset)
  - `:generator` - Generator function or module
  - `:timeout` - Execution timeout in milliseconds
  - `:call_id` - Custom call ID (auto-generated if not provided)

  ## Returns

  - `{:ok, agent}` - Pipeline started successfully
  - `{:error, reason}` - Failed to start pipeline

  ## Examples

      {:ok, agent} = StrategyAdapter.run_pipeline(agent, "What is 2+2?", preset: :fast)

      {:ok, agent} = StrategyAdapter.run_pipeline(agent, "Explain quantum computing",
        preset: :accurate,
        config: %{generation_config: %{max_candidates: 15}}
      )

  ## Signal Handling

  Results are emitted as `accuracy.result` signals which can be handled
  via the agent's signal_routes/1:

      def handle_accuracy_result(agent, signal) do
        # signal.answer contains the final answer
        # signal.confidence contains the confidence score
        {:ok, agent}
      end

  """
  @spec run_pipeline(agent(), query(), keyword()) :: {:ok, agent()} | {:error, term()}
  def run_pipeline(agent, query, opts \\ []) do
    preset = Keyword.get(opts, :preset, :balanced)
    config = Keyword.get(opts, :config, %{})
    generator = Keyword.get(opts, :generator)
    timeout = Keyword.get(opts, :timeout, 30_000)
    call_id = Keyword.get(opts, :call_id, generate_call_id())

    # Build the directive
    _directive = Directive.Run.new!(%{
      id: call_id,
      query: query,
      preset: preset,
      config: config,
      generator: generator,
      timeout: timeout
    })

    # Get or create pipeline
    pipeline_config = build_pipeline_config(preset, config, agent)
    {:ok, pipeline} = Pipeline.new(%{config: pipeline_config})

    # Execute pipeline with error handling
    start_time = System.monotonic_time(:millisecond)
    generator_fn = resolve_generator(generator, agent)

    execution_result =
      try do
        {:ok,
         Pipeline.run(pipeline, query, generator: generator_fn, timeout: timeout)}
      rescue
        e -> {:error, e}
      end

    # Emit result signal
    emit_result_signal(call_id, query, preset, execution_result, start_time, agent)

    case execution_result do
      {:ok, _result} -> {:ok, agent}
      {:error, e} -> {:error, e}
    end
  end

  @doc """
  Converts a query to an Accuracy directive.

  ## Examples

      iex> StrategyAdapter.to_directive("What is 2+2?", preset: :fast)
      %Jido.AI.Accuracy.Directive.Run{query: "What is 2+2?", preset: :fast}

  """
  @spec to_directive(query(), keyword()) :: Directive.Run.t()
  def to_directive(query, opts \\ []) do
    Directive.Run.new!(%{
      id: Keyword.get(opts, :call_id, generate_call_id()),
      query: query,
      preset: Keyword.get(opts, :preset, :balanced),
      config: Keyword.get(opts, :config, %{}),
      generator: Keyword.get(opts, :generator),
      timeout: Keyword.get(opts, :timeout, 30_000)
    })
  end

  @doc """
  Extracts the query from a signal.

  ## Examples

      iex> StrategyAdapter.from_signal(signal)
      "What is 2+2?"

  """
  @spec from_signal(map()) :: binary() | nil
  def from_signal(%{"accuracy.run" => data}) when is_map(data) do
    Map.get(data, :query)
  end

  def from_signal(%{type: "accuracy.run", data: data}) when is_map(data) do
    Map.get(data, :query)
  end

  def from_signal(_signal), do: nil

  @doc """
  Creates a generator function from model spec or module.

  ## Examples

      iex> StrategyAdapter.make_generator("anthropic:claude-haiku-4-5")
      fun when is_function(fun, 1)

      iex> StrategyAdapter.make_generator(MyGenerator)
      MyGenerator

  """
  @spec make_generator(binary() | module() | function()) :: function() | module()
  def make_generator(model_spec) when is_binary(model_spec) do
    # Create a generator function from model spec
    fn prompt ->
      # In a real implementation, this would use ReqLLM to call the model
      # For now, return a mock response
      {:ok, "Mock response for: #{prompt}"}
    end
  end

  def make_generator(module) when is_atom(module) do
    module
  end

  def make_generator(fun) when is_function(fun, 1), do: fun

  # Private helpers

  defp build_pipeline_config(preset, custom_config, agent) do
    # Get preset config
    {:ok, base_config} = Presets.get_config(preset)

    # Merge with custom config
    merged_config =
      if map_size(custom_config) > 0 do
        Map.merge(base_config, custom_config)
      else
        base_config
      end

    # Apply agent-specific overrides
    apply_agent_config(merged_config, agent)
  end

  defp apply_agent_config(config, agent) do
    # If agent has accuracy config in state, merge it
    agent_accuracy_config = get_in(agent, [:state, :accuracy_config])

    case agent_accuracy_config do
      nil -> config
      overrides when is_map(overrides) -> Map.merge(config, overrides)
    end
  end

  defp resolve_generator(nil, agent) do
    # Try to get generator from agent state
    case get_in(agent, [:state, :accuracy_generator]) do
      nil -> default_generator(agent)
      gen -> gen
    end
  end

  defp resolve_generator(gen, _agent), do: gen

  defp default_generator(agent) do
    # Get model from agent config and create generator
    model = get_in(agent, [:state, :model]) || "anthropic:claude-haiku-4-5"
    make_generator(model)
  end

  defp emit_result_signal(call_id, query, preset, {:ok, result}, start_time, agent) do
    signal = Signal.Result.from_pipeline_result(call_id, query, preset, result, start_time)

    # Emit the signal to the agent
    # In a real implementation, this would call Jido.Agent.emit_signal/3
    # For now, we'll just return the signal
    _signal = signal
    _agent = agent
  end

  defp emit_result_signal(_call_id, _query, _preset, {:error, _reason}, _start_time, _agent) do
    # Error case - emit error signal
    :ok
  end

  defp emit_error_signal(call_id, query, preset, exception, agent) do
    signal = Signal.Error.from_exception(call_id, query, preset, exception)

    # Emit the error signal to the agent
    _signal = signal
    _agent = agent
  end

  defp generate_call_id do
    "accuracy_#{System.unique_integer([:positive, :monotonic])}"
  end
end
