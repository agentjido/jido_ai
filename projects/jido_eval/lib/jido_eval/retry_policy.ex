defmodule Jido.Eval.RetryPolicy do
  @moduledoc """
  Configuration for retry behavior in Jido Eval.

  Defines how failed operations should be retried with exponential backoff
  and jitter support.

  ## Examples

      iex> policy = %Jido.Eval.RetryPolicy{}
      iex> policy.max_retries
      3
      
      iex> policy = %Jido.Eval.RetryPolicy{max_retries: 5, base_delay: 2000}
      iex> policy.max_retries
      5
  """

  use TypedStruct

  typedstruct do
    @typedoc "Retry policy configuration"

    field(:max_retries, non_neg_integer(), default: 3)
    field(:base_delay, non_neg_integer(), default: 1000)
    field(:max_delay, non_neg_integer(), default: 60_000)
    field(:jitter, boolean(), default: true)
    field(:retryable_errors, [atom()], default: [:timeout, :rate_limit, :server_error])
  end
end
