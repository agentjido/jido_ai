defmodule JidoAI.Skills.Exec do
  @moduledoc """
  A skill that provides code execution capabilities for agents.

  This skill includes actions for executing code in various languages
  within a controlled environment.
  """

  use Jido.Skill,
    name: "exec",
    description: "Provides code execution capabilities",
    category: "Development", 
    tags: ["code", "execution", "programming"],
    vsn: "1.0.0",
    opts_key: :exec,
    opts_schema: [],
    signal_patterns: [
      "jido.exec.**"
    ],
    actions: [
      JidoAI.Actions.RunCode
    ]

  alias Jido.Instruction

  @impl true
  @spec router(keyword()) :: [Jido.Signal.Router.Route.t()]
  def router(_opts) do
    [
      %Jido.Signal.Router.Route{
        path: "jido.exec.run",
        target: %Instruction{action: JidoAI.Actions.RunCode},
        priority: 0
      }
    ]
  end

  @impl true
  @spec handle_signal(Jido.Signal.t(), Jido.Skill.t()) ::
          {:ok, Jido.Signal.t()} | {:error, term()}
  def handle_signal(%Jido.Signal{} = signal, _skill) do
    {:ok, signal}
  end

  @impl true
  @spec transform_result(Jido.Signal.t(), term(), Jido.Skill.t()) ::
          {:ok, term()} | {:error, any()}
  def transform_result(_signal, result, _skill) do
    {:ok, result}
  end
end
