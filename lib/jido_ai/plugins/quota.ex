require Jido.AI.Actions.Quota.GetStatus
require Jido.AI.Actions.Quota.Reset

defmodule Jido.AI.Plugins.Quota do
  @moduledoc """
  Cross-cutting quota and budget enforcement plugin.

  Tracks rolling request/token usage from `ai.usage` signals and rewrites
  budgeted request/query signals to `ai.request.error` when configured limits
  are reached.

  ## Quota State Keys

  `mount/2` stores quota runtime state under state key `:quota` with:

  - `enabled` - enable/disable quota enforcement
  - `scope` - quota counter namespace in `Jido.AI.Quota.Store`
  - `window_ms` - rolling quota window size in milliseconds
  - `max_requests` - optional request budget for the window
  - `max_total_tokens` - optional token budget for the window
  - `error_message` - user-facing rejection message

  These keys are used by `handle_signal/2` and quota action routes
  (`quota.status`, `quota.reset`).

  ## Usage Accounting

  - `ai.usage` increments usage counters (`requests`, `total_tokens`) for the
    active `scope`.
  - Token accounting reads `total_tokens` first, then falls back to
    `input_tokens + output_tokens`.
  - Counters reset to zero when usage is outside the configured `window_ms`.

  ## Budget Rejection Contract

  When quota `enabled: true` and usage is at/over budget for either
  `max_requests` or `max_total_tokens`, budgeted signals (`chat.*`,
  `ai.*.query`, `reasoning.*.run`) are rewritten to `ai.request.error` with:

  - `request_id` from request/call correlation fields when present
  - `reason: :quota_exceeded`
  - `message` from `error_message` (default: `"quota exceeded for current window"`)

  ## Usage

  ```elixir
  use Jido.AI.Agent,
    name: "quota_guarded_assistant",
    plugins: [
      {Jido.AI.Plugins.Quota,
       %{
         enabled: true,
         scope: "assistant_ops",
         window_ms: 60_000,
         max_requests: 50,
         max_total_tokens: 20_000,
         error_message: "quota exceeded for current window"
       }}
    ]
  ```
  """

  use Jido.Plugin,
    name: "quota",
    state_key: :quota,
    actions: [
      Jido.AI.Actions.Quota.GetStatus,
      Jido.AI.Actions.Quota.Reset
    ],
    description: "Tracks usage and enforces rolling request/token budgets",
    category: "ai",
    tags: ["quota", "budget", "usage"],
    vsn: "1.0.0"

  alias Jido.AI.Quota.Store
  alias Jido.AI.Signal
  alias Jido.AI.Signal.Helpers, as: SignalHelpers
  alias Jido.Signal, as: BaseSignal

  @budgeted_signals [
    "chat.message",
    "chat.simple",
    "chat.complete",
    "chat.generate_object",
    "ai.react.query",
    "ai.cod.query",
    "ai.aot.query",
    "ai.cot.query",
    "ai.tot.query",
    "ai.got.query",
    "ai.trm.query",
    "ai.adaptive.query"
  ]

  @impl true
  def mount(agent, config) do
    scope =
      Map.get(config, :scope) ||
        if(is_map(agent) and is_binary(agent.id), do: agent.id, else: "default")

    {:ok,
     %{
       enabled: Map.get(config, :enabled, true),
       scope: scope,
       window_ms: Map.get(config, :window_ms, 60_000),
       max_requests: Map.get(config, :max_requests),
       max_total_tokens: Map.get(config, :max_total_tokens),
       error_message: Map.get(config, :error_message, "quota exceeded for current window")
     }}
  end

  def schema do
    Zoi.object(%{
      enabled: Zoi.boolean(description: "Enable quota enforcement") |> Zoi.default(true),
      scope: Zoi.string(description: "Quota scope key") |> Zoi.optional(),
      window_ms: Zoi.integer(description: "Rolling quota window in milliseconds") |> Zoi.default(60_000),
      max_requests:
        Zoi.integer(description: "Maximum requests per window (nil disables request budget)")
        |> Zoi.optional(),
      max_total_tokens:
        Zoi.integer(description: "Maximum total tokens per window (nil disables token budget)")
        |> Zoi.optional(),
      error_message: Zoi.string(description: "User-facing quota rejection message") |> Zoi.default("quota exceeded")
    })
  end

  @impl true
  def signal_routes(_config) do
    [
      {"quota.status", Jido.AI.Actions.Quota.GetStatus},
      {"quota.reset", Jido.AI.Actions.Quota.Reset}
    ]
  end

  @impl true
  def handle_signal(%BaseSignal{type: "ai.usage", data: data}, context) when is_map(data) do
    state = plugin_state(context)
    scope = state[:scope] || "default"
    window_ms = state[:window_ms] || 60_000
    tokens = extract_total_tokens(data)
    _usage = Store.add_usage(scope, tokens, window_ms)
    {:ok, :continue}
  end

  def handle_signal(%BaseSignal{} = signal, context) do
    state = plugin_state(context)

    if state[:enabled] == true and budgeted_signal?(signal.type) and over_budget?(state) do
      {:ok, {:continue, rewrite_quota_exceeded(signal, state)}}
    else
      {:ok, :continue}
    end
  end

  def handle_signal(_signal, _context), do: {:ok, :continue}

  defp over_budget?(state) do
    scope = state[:scope] || "default"
    window_ms = state[:window_ms] || 60_000

    status =
      Store.status(
        scope,
        %{
          max_requests: state[:max_requests],
          max_total_tokens: state[:max_total_tokens]
        },
        window_ms
      )

    status.over_budget? == true
  end

  defp rewrite_quota_exceeded(%BaseSignal{} = signal, state) do
    request_id = SignalHelpers.correlation_id(signal.data) || "req_#{Jido.Util.generate_id()}"

    Signal.RequestError.new!(%{
      request_id: request_id,
      reason: :quota_exceeded,
      message: state[:error_message] || "quota exceeded for current window"
    })
  end

  defp extract_total_tokens(data) when is_map(data) do
    total = Map.get(data, :total_tokens, Map.get(data, "total_tokens"))

    cond do
      is_integer(total) and total >= 0 ->
        total

      true ->
        input_tokens = Map.get(data, :input_tokens, Map.get(data, "input_tokens", 0))
        output_tokens = Map.get(data, :output_tokens, Map.get(data, "output_tokens", 0))
        max(input_tokens, 0) + max(output_tokens, 0)
    end
  end

  defp budgeted_signal?(type) when is_binary(type) do
    type in @budgeted_signals or
      (String.starts_with?(type, "reasoning.") and String.ends_with?(type, ".run"))
  end

  defp budgeted_signal?(_), do: false

  defp plugin_state(%{agent: %{state: state}, plugin_instance: %{state_key: state_key}})
       when is_map(state) and is_atom(state_key) do
    Map.get(state, state_key, %{})
  end

  defp plugin_state(_), do: %{}
end
