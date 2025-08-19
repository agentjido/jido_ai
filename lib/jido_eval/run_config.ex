defmodule Jido.Eval.RunConfig do
  @moduledoc """
  Configuration for evaluation run execution.

  Controls runtime behavior including timeouts, parallelism, and caching.

  ## Examples

      iex> config = %Jido.Eval.RunConfig{}
      iex> config.max_workers
      16
      
      iex> config = %Jido.Eval.RunConfig{timeout: 300_000, max_workers: 8}
      iex> config.timeout
      300000
  """

  use TypedStruct

  typedstruct do
    @typedoc "Execution configuration for evaluation runs"

    field(:run_id, String.t() | nil, default: nil)
    field(:timeout, non_neg_integer(), default: 180_000)
    field(:max_workers, non_neg_integer(), default: 16)
    field(:seed, non_neg_integer(), default: 42)
    field(:retry_policy, Jido.Eval.RetryPolicy.t(), default: %Jido.Eval.RetryPolicy{})
    field(:enable_caching, boolean(), default: false)
    field(:telemetry_prefix, [atom()], default: [:jido, :eval])
    field(:enable_real_time_events, boolean(), default: true)
  end
end
