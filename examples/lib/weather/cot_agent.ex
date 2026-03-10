defmodule Jido.AI.Examples.Weather.CoTAgent do
  @moduledoc """
  Chain-of-Thought weather advisor.

  Useful for transparent, step-by-step decision guidance when users want to
  understand the reasoning behind weather choices.

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.Weather.CoTAgent \\
        "How should I decide between running outdoors or at the gym if rain is likely?"
  """

  alias Jido.AI.Examples.Weather.LiveContext

  use Jido.AI.CoTAgent,
    name: "weather_cot_agent",
    description: "Step-by-step weather decision advisor",
    system_prompt: """
    You are a weather decision coach.

    Think step-by-step and clearly separate:
    1) known facts
    2) assumptions
    3) recommendation

    When data is missing, explain what would most change the recommendation.
    """

  @doc "Returns the CLI adapter used by `mix jido_ai` for this example."
  @spec cli_adapter() :: module()
  def cli_adapter, do: Jido.AI.Reasoning.ChainOfThought.CLIAdapter

  @doc """
  Analyze a weather decision with explicit reasoning steps.
  """
  @spec weather_decision_sync(pid(), String.t(), keyword()) :: {:ok, any()} | {:error, term()}
  def weather_decision_sync(pid, question, opts \\ []) do
    prompt = """
    Analyze this weather decision with explicit reasoning:
    #{question}

    Return:
    - Key factors
    - Decision logic
    - Final recommendation
    """

    think_sync(pid, prompt, opts)
  end

  @impl true
  def on_before_cmd(agent, {:cot_start, %{prompt: prompt} = params}) do
    case LiveContext.enrich_prompt(prompt) do
      {:ok, enriched_prompt} -> super(agent, {:cot_start, %{params | prompt: enriched_prompt}})
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def on_before_cmd(agent, action), do: super(agent, action)
end
