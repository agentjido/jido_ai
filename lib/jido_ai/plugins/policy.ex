defmodule Jido.AI.Plugins.Policy do
  @moduledoc """
  Default-on policy middleware for AI signal enforcement.

  This plugin intercepts inbound/internal AI signals and applies policy checks
  before routing continues through strategies.
  """

  alias Jido.AI.Policy.Engine

  @config_schema Zoi.object(%{
                   mode: Zoi.enum([:enforce, :report_only]) |> Zoi.default(:enforce),
                   query_max_length: Zoi.integer() |> Zoi.default(100_000),
                   delta_max_length: Zoi.integer() |> Zoi.default(4_096),
                   result_max_length: Zoi.integer() |> Zoi.default(50_000),
                   block_injection_patterns: Zoi.boolean() |> Zoi.default(true),
                   strip_control_chars: Zoi.boolean() |> Zoi.default(true),
                   redact_violation_details: Zoi.boolean() |> Zoi.default(true)
                 })

  use Jido.Plugin,
    name: "ai_policy",
    description: "AI signal policy enforcement middleware",
    category: "ai",
    tags: ["policy", "security", "middleware"],
    state_key: :ai_policy,
    actions: [],
    singleton: true,
    signal_patterns: ["ai.*"],
    config_schema: @config_schema

  @impl Jido.Plugin
  def mount(_agent, _config) do
    {:ok, %{}}
  end

  @impl Jido.Plugin
  def signal_routes(_config) do
    []
  end

  @impl Jido.Plugin
  def handle_signal(signal, context) do
    Engine.handle(signal, context[:config] || %{})
  end
end
