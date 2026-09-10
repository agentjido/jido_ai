defmodule Jido.AI.Agent.InitialState do
  @moduledoc false
  alias Jido.AI.{Configuration, Context, History, Profile}

  def import(source, state, opts) do
    with {:ok, opts} <- options(opts),
         {:ok, definition} <- definition(source),
         :ok <- thread_key(state),
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
    # Plugin-owned state requires its own versioned conversion. Core still
    # validates each admitted domain field, its defaults, and the final size.
    Profile.fields(state, [:context | Keyword.keys(definition.schema.fields)], "initial_state")
  end

  defp thread_key(%{thread: %Context{}}), do: legacy_thread_error()
  defp thread_key(%{"thread" => %Context{}}), do: legacy_thread_error()
  defp thread_key(_), do: :ok

  defp legacy_thread_error,
    do: error("initial_state[:thread] is no longer supported for AI context; use :context")

  defp context(%{context: input} = state, profile) do
    with true <- profile.memory.history != nil,
         false <- Map.has_key?(state, profile.memory.history),
         {:ok, context} <- normalize_context(input),
         true <- is_binary(context.id) and context.id != "" and is_list(context.entries),
         true <- is_nil(context.system_prompt) or is_binary(context.system_prompt),
         :ok <- Jido.Action.validate_static_data(context),
         {:ok, values} <- History.prepare_entries(context.entries),
         {:ok, messages} <- History.messages(values),
         {:ok, open} <- History.open_tool_calls(messages),
         true <- map_size(open) == 0 do
      {:ok, state |> Map.delete(:context) |> Map.put(profile.memory.history, values), context.system_prompt}
    else
      {:error, _} = failure -> failure
      _ -> error("Expected a portable complete Context, a profile with history, and no competing history field")
    end
  end

  defp context(state, _), do: {:ok, state, nil}

  defp normalize_context(%Context{} = context), do: {:ok, context}

  defp normalize_context(input) do
    with {:ok, fields} <- Profile.fields(input, [:id, :entries, :system_prompt], "initial_state.context"),
         do: Context.coerce(fields)
  end

  defp error(message), do: Profile.error("initial_state", message)
end
