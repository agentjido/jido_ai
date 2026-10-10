defmodule Jido.AI.SystemOne.Client do
  @moduledoc """
  Contract for a System One decision-model client.

  A System One model (for example TypeSafe's Jev, Cloudflare's Clef, or a self-hosted
  model that serves the `/v1/systemone` wire format) takes a `state` and a map of typed
  questions (`noul`, `choice`, `score`) and returns a probability for every allowed
  answer. `Jido.AI.Reasoning.ReAct.Transformers.SystemOne` uses such a client to gate
  tools and pick a model tier before each ReAct turn.

  Jido.AI ships no HTTP client for these APIs. Any module that implements `evaluate/3`
  works, so the provider, credentials and transport stay in your application. The
  [`system_one_client`](https://hex.pm/packages/system_one_client) package satisfies
  this contract as-is: pass `client: SystemOneClient`.

  ## Answer shape

  `evaluate/3` returns `{:ok, answers, meta}` where `answers` is keyed by question id
  (strings) and each answer is a map or struct with, by question type:

    * `noul`: `:noul`, the probability that the condition holds
    * `choice`: `:probabilities`, a map of option name to probability
    * `score`: `:score`, the probability-weighted level (0 is the lowest level)

  `meta` may carry `:latency_ms` and `:model`. Any other keys are ignored.

  Return `{:error, reason}` for every failure; callers treat errors as "no decision"
  and fall back to their configured behaviour.
  """

  @type question_id :: String.t()
  @type answer :: %{
          optional(:noul) => number(),
          optional(:probabilities) => %{optional(String.t()) => number()},
          optional(:score) => number()
        }
  @type meta :: %{optional(:latency_ms) => non_neg_integer(), optional(:model) => String.t()}

  @callback evaluate(state :: term(), questions :: %{question_id() => map()}, opts :: keyword()) ::
              {:ok, %{question_id() => answer()}, meta()} | {:error, term()}
end
