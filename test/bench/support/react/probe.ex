defmodule JidoAI.Bench.ReAct.Probe do
  @moduledoc "Run one deterministic ReAct state-growth probe."

  alias JidoAI.Bench.ReAct.{Agent, FactTrace, MemorySampler, Model}

  @type status :: :completed | :canonical_item_limit | :error

  @type report :: %{
          requested_rounds: pos_integer(),
          status: status(),
          model_calls: non_neg_integer(),
          executed_tool_rounds: non_neg_integer(),
          replies_left: non_neg_integer(),
          elapsed_ms: non_neg_integer(),
          error_item_count: non_neg_integer() | nil,
          error_path: list() | nil,
          fact_count: non_neg_integer(),
          largest_fact_items: non_neg_integer(),
          largest_fact_external_bytes: non_neg_integer(),
          largest_fact_round: non_neg_integer(),
          largest_fact_shape: String.t() | nil,
          largest_fact_child_items: [non_neg_integer()],
          fact_rounds: map()
        }

  @spec run(pos_integer()) :: report()
  def run(requested_rounds) when requested_rounds in 1..20 do
    round_counter = :atomics.new(1, signed: false)
    tool_counter = :atomics.new(1, signed: false)
    model = Model.start!(requested_rounds, round_counter)
    trace = FactTrace.start!(round_counter)

    try do
      started_at = System.monotonic_time(:millisecond)

      result = execute(requested_rounds, tool_counter)
      elapsed_ms = max(System.monotonic_time(:millisecond) - started_at, 0)
      facts = FactTrace.stop!(trace)
      model_summary = Model.summary(model)
      {status, error_item_count, error_path} = classify(result)

      %{
        requested_rounds: requested_rounds,
        status: status,
        model_calls: model_summary.calls,
        executed_tool_rounds: :atomics.get(tool_counter, 1),
        replies_left: model_summary.replies_left,
        elapsed_ms: elapsed_ms,
        error: error_summary(result),
        result_sizes: term_sizes(result),
        error_item_count: error_item_count,
        error_path: error_path,
        fact_count: facts.fact_count,
        largest_fact_items: facts.largest_items,
        largest_fact_external_bytes: facts.largest_external_bytes,
        largest_fact_round: facts.largest_round,
        largest_fact_shape: facts.largest_shape,
        largest_fact_child_items: facts.largest_child_items,
        fact_rounds: facts.rounds
      }
    after
      FactTrace.abort!(trace)
      if Process.alive?(model), do: Model.stop(model)
    end
  end

  @spec run_memory(pos_integer()) :: map()
  def run_memory(requested_rounds) when requested_rounds in 1..20 do
    round_counter = :atomics.new(1, signed: false)
    tool_counter = :atomics.new(1, signed: false)
    model = Model.start!(requested_rounds, round_counter)
    sampler = MemorySampler.start!()

    try do
      started_at = System.monotonic_time(:millisecond)
      result = execute(requested_rounds, tool_counter)
      elapsed_ms = max(System.monotonic_time(:millisecond) - started_at, 0)
      memory = MemorySampler.stop!(sampler)
      model_summary = Model.summary(model)
      {status, error_item_count, error_path} = classify(result)

      %{
        requested_rounds: requested_rounds,
        status: status,
        model_calls: model_summary.calls,
        executed_tool_rounds: :atomics.get(tool_counter, 1),
        replies_left: model_summary.replies_left,
        elapsed_ms: elapsed_ms,
        error: error_summary(result),
        result_sizes: term_sizes(result),
        error_item_count: error_item_count,
        error_path: error_path,
        vm_memory: memory
      }
    after
      if Process.alive?(sampler.pid), do: MemorySampler.stop!(sampler)
      if Process.alive?(model), do: Model.stop(model)
    end
  end

  defp execute(requested_rounds, tool_counter) do
    signal =
      Agent.request_signal!(%{
        input: "Call echo once per round, then answer done.",
        model: "openai:gpt-4o-mini",
        options: %{
          api_key: "offline",
          max_retries: 0,
          max_tokens: 1_000,
          req_http_options: [plug: {Req.Test, Model}],
          temperature: 0.0
        },
        limits: %{
          model_calls: requested_rounds + 1,
          tool_rounds: requested_rounds,
          tool_calls: requested_rounds,
          retries: 0,
          elapsed_ms: 120_000
        }
      })

    Agent.cmd(
      Agent.instantiate!(id: "state-growth-#{requested_rounds}"),
      signal,
      context: %{bench_tool_counter: tool_counter}
    )
  end

  defp classify({:ok, _agent, _directives}), do: {:completed, nil, nil}

  defp classify({:error, error}) do
    case canonical_error(error) do
      %Runic.Identity.CanonicalError{reason: {:limit, :item_count, count}, path: path} ->
        {:canonical_item_limit, count, path}

      _other ->
        {:error, nil, nil}
    end
  end

  defp canonical_error(%Runic.Identity.CanonicalError{} = error), do: error

  defp canonical_error(%{details: %{reason: {%Runic.Identity.CanonicalError{} = error, _stack}}}),
    do: error

  defp canonical_error(_error), do: nil

  defp error_summary({:error, error}), do: inspect(error, limit: 20, printable_limit: 2_000)
  defp error_summary(_result), do: nil

  defp term_sizes(term) do
    word_size = :erlang.system_info(:wordsize)

    %{
      external_bytes: :erlang.external_size(term),
      shared_heap_bytes: :erts_debug.size(term) * word_size,
      flat_heap_bytes: :erts_debug.flat_size(term) * word_size
    }
  end
end
