defmodule Jido.AI.Authoring do
  @moduledoc "Lowers validated AI profiles into an ordinary Jido Agent definition."
  alias Jido.AI.{Profile, Runtime}

  defmodule Ref do
    @moduledoc "A static route reference to one declared AI profile."
    defstruct [:id]
  end

  @doc "Makes an AI route reference in source attributes passed to lower/2."
  def ai(id), do: %Ref{id: id}

  @doc false
  def request_binding(%Jido.Agent{routes: routes}, %Jido.Signal{data: data} = signal) when is_map(data) do
    with {:ok, router} <- Jido.Signal.Router.new(routes),
         {:ok, [{target, %{profile_id: id} = defaults}]} <-
           Jido.Signal.Router.route(router, signal),
         true <- target in [Jido.AI.Runtime.Run, Jido.AI.Session.Start] do
      %{
        id: id,
        mode: if(target == Jido.AI.Runtime.Run, do: :turn, else: :session),
        input: Map.merge(defaults, data)
      }
    else
      _ -> nil
    end
  end

  def request_binding(_, _), do: nil

  @doc false
  def request_method(agent, signal) do
    with %{id: id} <- request_binding(agent, signal),
         {Runtime.Plugin, opts} <- Enum.find(agent.plugins, &(elem(&1, 0) == Runtime.Plugin)),
         %Profile{reasoning: %{method: method}} <- opts[:profiles][id] do
      method
    else
      _ -> :unknown
    end
  end

  @doc "Lowers profiles on a neutral Agent or static attribute map, then applies core validation."
  def lower(%Jido.Agent{id: nil, state: nil} = agent, profiles) do
    attrs = agent |> Jido.Agent.to_map() |> Map.drop([:id, :state])
    with {:ok, attrs} <- lower_config(attrs, profiles), do: Jido.Agent.new(attrs)
  end

  def lower(%Jido.Agent{}, _), do: Profile.error("agent", "Expected a neutral Agent definition")

  def lower(attrs, profiles) do
    with {:ok, attrs} <- Jido.Agent.Authoring.attrs(attrs),
         {:ok, routes} <- Jido.Agent.Authoring.routes(Map.get(attrs, :routes, [])),
         {:ok, base} <- Jido.Agent.new(Map.delete(attrs, :routes)),
         %Jido.Agent{id: nil, state: nil} <- base,
         config =
           base |> Jido.Agent.to_map() |> Map.drop([:id, :state]) |> Map.put(:routes, routes),
         {:ok, config} <- lower_config(config, profiles) do
      Jido.Agent.new(config)
    else
      {:error, _} = error -> error
      _ -> Profile.error("agent", "Expected a neutral Agent definition")
    end
  end

  @doc false
  def lower_config(config, values) do
    Code.ensure_compiled!(Runtime.Plugin)
    Code.ensure_compiled!(Jido.AI.Configuration.Apply)
    Code.ensure_compiled!(Jido.AI.Context.Operations.Apply)
    Code.ensure_compiled!(Jido.AI.Context.Operations.Plugin)

    with {:ok, pairs} <- Profile.traverse(values, &Profile.source/1),
         profiles = Enum.map(pairs, &elem(&1, 0)),
         true <- length(profiles) == length(Enum.uniq_by(profiles, & &1.id)),
         :ok <- fields(config.schema, profiles),
         false <-
           Enum.any?(
             config.plugins,
             &(plugin_module(&1) in [
                 Runtime.Plugin,
                 Jido.AI.Session.Plugin,
                 Jido.AI.Context.Operations.Plugin
               ])
           ),
         {:ok, flows} <-
           Profile.traverse(profiles, fn profile ->
             with {:ok, flow} <- flow(profile), do: {:ok, {profile.id, flow}}
           end),
         {:ok, extra} <- Profile.traverse(pairs, &routes/1),
         {:ok, routes} <-
           Profile.traverse(config.routes ++ List.flatten(extra), &route(&1, Map.new(flows))),
         sessions = Enum.filter(profiles, &(&1.requests.mode == :session)),
         histories =
           Map.new(
             Enum.filter(profiles, &(&1.memory.history != nil)),
             &{&1.id, &1.memory.history}
           ),
         {:ok, internal_routes} <- Jido.AI.Session.routes(sessions),
         {:ok, config_routes} <-
           Jido.Agent.Authoring.routes(
             if(profiles == [],
               do: [],
               else:
                 Jido.AI.Configuration.routes() ++
                   if(map_size(histories) == 0, do: [], else: Jido.AI.Context.Operations.routes())
             )
           ),
         routes = routes ++ internal_routes ++ config_routes,
         :ok <- route_conflicts(routes) do
      plugins =
        if profiles == [],
          do: config.plugins,
          else: config.plugins ++ [{Runtime.Plugin, [profiles: Map.new(profiles, &{&1.id, &1})]}]

      skill_sources = Map.new(Enum.filter(sessions, &(&1.skills != nil)), &{&1.id, &1.skills})
      session_opts = if map_size(skill_sources) == 0, do: [], else: [skills: skill_sources]

      plugins =
        if sessions == [], do: plugins, else: plugins ++ [{Jido.AI.Session.Plugin, session_opts}]

      plugins =
        if map_size(histories) == 0,
          do: plugins,
          else: plugins ++ [{Jido.AI.Context.Operations.Plugin, [profiles: histories]}]

      {:ok, %{config | routes: routes, plugins: plugins}}
    else
      true -> Profile.error("plugins", "The AI binding Plugin is managed by the lowerer")
      false -> Profile.error("profiles", "Duplicate profile ID")
      error -> error
    end
  end

  defp fields(%Zoi.Types.Map{fields: fields}, profiles) do
    Enum.reduce_while(profiles, :ok, fn profile, :ok ->
      history = profile.memory.history

      error =
        cond do
          not Keyword.has_key?(fields, profile.result.into) ->
            Profile.error("result.into", "Output must select a declared domain field")

          history != nil and
              (not Keyword.has_key?(fields, history) or history == profile.result.into) ->
            Profile.error(
              "memory.history",
              "History must select a declared field separate from the result"
            )

          true ->
            nil
        end

      if error, do: {:halt, error}, else: {:cont, :ok}
    end)
  end

  defp fields(_, _), do: Profile.error("agent.schema", "Expected a field-based Zoi schema")

  defp plugin_module({module, _}), do: module
  defp plugin_module(module), do: module

  defp routes({profile, paths}) do
    Profile.traverse(paths, &Jido.Agent.Authoring.route(&1, ai(profile.id), []))
  end

  defp route(%{target: {%Ref{id: id}, defaults}} = route, flows) when is_map(defaults) do
    with {:ok, flow} <- fetch(flows, id) do
      case flow do
        {target, fixed} -> {:ok, %{route | target: {target, Map.merge(defaults, fixed)}}}
        _ -> {:ok, %{route | target: {flow, defaults}}}
      end
    end
  end

  defp route(%{target: %Ref{id: id}} = route, flows) do
    with {:ok, flow} <- fetch(flows, id), do: {:ok, %{route | target: flow}}
  end

  defp route(%{target: {{:jido_agent_extension, :ai, id}, defaults}} = route, flows)
       when is_map(defaults) do
    route(%{route | target: {%Ref{id: id}, defaults}}, flows)
  end

  defp route(%{target: {:jido_agent_extension, :ai, id}} = route, flows) do
    route(%{route | target: %Ref{id: id}}, flows)
  end

  defp route(route, _), do: {:ok, route}

  defp fetch(flows, id) do
    case Map.fetch(flows, id) do
      {:ok, flow} -> {:ok, flow}
      :error -> Profile.error("routes", "Unknown AI profile #{inspect(id)}")
    end
  end

  defp route_conflicts(routes) do
    keys = Enum.map(routes, &{&1.path, &1.match, &1.priority})

    if keys == Enum.uniq(keys),
      do: :ok,
      else: Profile.error("routes", "Conflicting route bindings")
  end

  defp flow(%{requests: %{mode: :session}} = profile),
    do: Jido.AI.Session.admission_target(profile)

  defp flow(profile), do: {:ok, {Jido.AI.Runtime.Run, %{profile_id: profile.id}}}

  @doc false
  def reasoning_flow(profile) do
    alias Jido.Flow.Builder, as: B

    Enum.each(
      [Runtime.Prepare, Runtime.CallModel, Runtime.Decide, Runtime.Plugin],
      &Code.ensure_compiled!/1
    )

    B.new(name: "ai_#{profile.id}", schema: Zoi.object(%{query: Jido.AI.Query.schema()}))
    |> B.step("prepare", Runtime.Prepare, %{profile_id: profile.id, query: B.input(:query)})
    |> B.dispatch("reason", Runtime.CallModel, Runtime.Decide, B.result("prepare"))
    |> B.output(B.result("reason"))
    |> B.build()
  end
end
