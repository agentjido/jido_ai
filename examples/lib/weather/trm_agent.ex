defmodule Jido.AI.Examples.Weather.TRMAgent do
  @moduledoc """
  TRM weather reliability coach.

  Useful for recursively refining weather-dependent plans until they are robust.

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.Weather.TRMAgent \\
        "Improve my severe-weather emergency plan for a 2-day power outage."
  """

  alias Jido.AI.Examples.Weather.LiveContext

  use Jido.AI.TRMAgent,
    name: "weather_trm_agent",
    description: "Recursive weather plan improver",
    # Keep CLI-friendly defaults so `mix jido_ai --agent ...` finishes within default timeout.
    max_supervision_steps: 2,
    act_threshold: 0.9

  @doc "Returns the CLI adapter used by `mix jido_ai` for this example."
  @spec cli_adapter() :: module()
  def cli_adapter, do: Jido.AI.Reasoning.TRM.CLIAdapter

  @doc """
  Refine a weather readiness scenario into a stronger plan.
  """
  @spec storm_readiness_sync(pid(), String.t(), keyword()) :: {:ok, any()} | {:error, term()}
  def storm_readiness_sync(pid, scenario, opts \\ []) do
    reason_sync(
      pid,
      "Stress test and improve this weather readiness scenario: #{scenario}. Iterate until the plan is robust, realistic, and safety-first.",
      opts
    )
  end

  @impl true
  def on_before_cmd(agent, {:trm_start, %{prompt: prompt} = params}) do
    case LiveContext.enrich_prompt(prompt) do
      {:ok, enriched_prompt} -> super(agent, {:trm_start, %{params | prompt: enriched_prompt}})
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def on_before_cmd(agent, action), do: super(agent, action)
end
