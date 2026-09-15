defmodule Jido.AI.Agent do
  @moduledoc """
  Adds the Jido AI authoring DSL to a normal Jido Agent.

  `use Jido.AI.Agent` uses `Jido.Agent` with the `Jido.AI.DSL` Spark extension.
  Spark collects and validates each `ai` declaration. The extension then lowers
  it to one inert `%Jido.AI.Profile{}`. Model and tool calls only occur after a
  request enters the Agent runtime.

  Agent definitions use the canonical `agent do` and `ai` DSL.

  Native AI routes require AgentServer admission. Use the generated `ask/3`
  helper or `Jido.AgentServer.call/3`. Direct `Jido.Agent.cmd/3` calls on these
  routes return a runtime validation error; they do not start model work.
  """

  defmacro __using__(opts) do
    quote location: :keep do
      use Jido.AI.Agent.Definition, unquote(opts)
    end
  end

  @doc "Builds an Agent value from application state without starting runtime work."
  def from_initial_state(source, state, opts \\ []) do
    Jido.AI.Agent.InitialState.import(source, state, opts)
  end

  @doc "Returns all declared AI profiles from an Agent module or definition."
  def profiles(module) when is_atom(module), do: profiles(module.definition())

  def profiles(%Jido.Agent{} = agent) do
    case Jido.AI.Configuration.options(agent) do
      {:ok, options} -> Keyword.fetch!(options, :profiles)
      {:error, _error} -> %{}
    end
  end

  @doc "Returns one declared AI profile or nil."
  def profile(source, id), do: Map.get(profiles(source), id)

  @doc "Returns the unique Action modules supplied by a list of skills."
  @spec tools_from_skills([module()]) :: [module()]
  def tools_from_skills(skill_modules) when is_list(skill_modules) do
    skill_modules
    |> Enum.flat_map(& &1.actions())
    |> Enum.uniq()
  end
end
