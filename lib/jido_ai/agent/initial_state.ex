defmodule Jido.AI.Agent.InitialState do
  @moduledoc false
  alias Jido.AI.{Configuration, Profile}
  alias Jido.AI.Thread.Projection

  def import(source, state, opts) do
    with {:ok, opts} <- options(opts),
         {:ok, definition} <- definition(source),
         {:ok, state} <- domain(state, definition),
         {:ok, profile} <- Configuration.profile(definition, opts[:profile]),
         {:ok, state, prompt} <- context(state, profile),
         {:ok, agent} <-
           Jido.Agent.instantiate(
             definition,
             Keyword.put(Keyword.take(opts, [:id]), :state, state)
           ),
         {:ok, agent} <- apply_prompt(agent, prompt, profile),
         :ok <- validate_state_size(agent, definition) do
      {:ok, agent}
    end
  end

  defp apply_prompt(agent, nil, _profile), do: {:ok, agent}

  defp apply_prompt(agent, prompt, profile),
    do: Configuration.direct(agent, :prompt, prompt, profile: profile.id)

  defp validate_state_size(agent, definition) do
    case Jido.AI.Runtime.StateSize.limit(definition) do
      nil -> :ok
      limit -> Jido.AI.Runtime.StateSize.validate(agent.state, limit, %{})
    end
  end

  defp options(opts) when is_list(opts) do
    if Keyword.keyword?(opts) and length(opts) == length(Keyword.keys(opts) |> Enum.uniq()) and
         Keyword.keys(opts) -- [:id, :profile] == [],
       do: {:ok, opts},
       else: error("Expected unique :id and :profile options")
  end

  defp options(_), do: error("Expected keyword options")

  defp definition(%Jido.Agent{} = source), do: Jido.Agent.new(source)

  defp definition(module) when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :definition, 0),
      do: module.definition() |> Jido.Agent.new(),
      else: error("Expected an Agent module or neutral definition")
  end

  defp definition(_), do: error("Expected an Agent module or neutral definition")

  defp domain(state, definition) do
    # Core validates each admitted domain field, its defaults, and the final size.
    Profile.fields(state, Keyword.keys(definition.schema.fields), "initial_state")
  end

  defp context(state, %{memory: %{history: nil}}), do: {:ok, state, nil}

  defp context(state, profile) do
    case Map.get(state, profile.memory.history) do
      nil ->
        {:ok, state, nil}

      input ->
        with {:ok, session} <- Jido.Session.decode(input),
             {:ok, messages} <- Projection.messages(session),
             {:ok, open} <- Projection.open_tool_calls(messages),
             true <- map_size(open) == 0,
             {:ok, selected} <- Projection.select(session),
             prompt = Map.get(selected.metadata, :system_prompt, selected.metadata["system_prompt"]),
             true <- is_nil(prompt) or is_binary(prompt) do
          {:ok, Map.put(state, profile.memory.history, session), prompt}
        else
          {:error, _} = failure -> failure
          _ -> error("Expected a canonical Session with a complete tool exchange")
        end
    end
  end

  defp error(message), do: Profile.error("initial_state", message)
end
