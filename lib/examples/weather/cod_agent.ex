defmodule Jido.AI.Examples.Weather.CoDAgent do
  @moduledoc """
  Chain-of-Draft weather advisor.

  Uses terse draft reasoning to provide low-latency weather guidance.

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.Weather.CoDAgent \\
        "Give me a fast weather-aware commute recommendation for tomorrow morning."
  """

  use Jido.AI.CoDAgent,
    name: "weather_cod_agent",
    description: "Concise weather advisor using Chain-of-Draft"

  @doc "Returns the CLI adapter used by `mix jido_ai` for this example."
  @spec cli_adapter() :: module()
  def cli_adapter, do: Jido.AI.Reasoning.ChainOfDraft.CLIAdapter

  @doc "Builds a concise weather recommendation with draft reasoning."
  @spec quick_plan_sync(pid(), String.t(), keyword()) :: {:ok, any()} | {:error, term()}
  def quick_plan_sync(pid, request, opts \\ []) do
    draft_sync(
      pid,
      "Provide a concise weather-aware recommendation with one backup option: #{request}",
      opts
    )
  end
end
