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
  def state_size_key, do: Jido.AI.Runtime.StateSize.metadata_key()

  @doc false
  def state_size_limit(source), do: Jido.AI.Runtime.StateSize.limit(source)

  @doc false
  def with_state_size_limit(config, nil), do: {:ok, config}

  def with_state_size_limit(%{metadata: metadata, schema: schema} = config, limit)
      when is_map(metadata) and is_integer(limit) and limit > 0 do
    {:ok,
     %{
       config
       | metadata: Map.put(metadata, state_size_key(), limit),
         schema: Zoi.refine(schema, {Jido.AI.Runtime.StateSize, :validate, [limit]})
     }}
  end

  def with_state_size_limit(_, _),
    do: Profile.error("max_state_size", "Expected a positive integer")

  @doc false
  def validate_state_size(state, limit, context),
    do: Jido.AI.Runtime.StateSize.validate(state, limit, context)

  @doc false
  def state_size_error?(error), do: Jido.AI.Runtime.StateSize.error?(error)

  @doc false
  def request_binding(agent, signal), do: Jido.AI.Runtime.Binding.request(agent, signal)

  @doc false
  def request_method(agent, signal), do: Jido.AI.Runtime.Binding.method(agent, signal)

  @doc "Lowers profiles on a neutral Agent or static attribute map, then applies core validation."
  def lower(%Jido.Agent{id: nil, state: nil} = agent, profiles) do
    attrs = agent |> Map.from_struct() |> Map.drop([:id, :state])
    with {:ok, attrs} <- lower_config(attrs, profiles), do: Jido.Agent.new(attrs)
  end

  def lower(%Jido.Agent{}, _), do: Profile.error("agent", "Expected a neutral Agent definition")

  def lower(attrs, profiles) do
    with {:ok, attrs} <- Jido.Agent.Authoring.attrs(attrs),
         {:ok, routes} <- Jido.Agent.Authoring.routes(Map.get(attrs, :routes, [])),
         {:ok, base} <- Jido.Agent.new(Map.delete(attrs, :routes)),
         %Jido.Agent{id: nil, state: nil} <- base,
         config =
           base |> Map.from_struct() |> Map.drop([:id, :state]) |> Map.put(:routes, routes),
         {:ok, config} <- lower_config(config, profiles) do
      Jido.Agent.new(config)
    else
      {:error, _} = error -> error
      _ -> Profile.error("agent", "Expected a neutral Agent definition")
    end
  end

  @doc false
  def lower_config(config, values) do
    ensure_plugin_compiled!(Runtime.Plugin)
    Code.ensure_compiled!(Jido.AI.Configuration.Apply)
    Code.ensure_compiled!(Jido.AI.Context.Operations.Apply)
    ensure_plugin_compiled!(Jido.AI.Context.Operations.Plugin)
    ensure_plugin_compiled!(Jido.AI.Session.Plugin)

    with {:ok, config} <- configured_state_size(config),
         {:ok, pairs} <- Profile.traverse(values, &Profile.source/1),
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
         internal_routes = prefer_explicit_observation_routes(internal_routes, routes),
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
          else:
            config.plugins ++
              [
                {Runtime.Plugin, [profiles: Map.new(profiles, &{&1.id, &1})]}
              ]

      skill_sources = Map.new(Enum.filter(sessions, &(&1.skills != nil)), &{&1.id, &1.skills})
      session_opts = if map_size(skill_sources) == 0, do: [], else: [skills: skill_sources]

      plugins =
        if sessions == [],
          do: plugins,
          else:
            plugins ++
              [
                {Jido.AI.Session.Plugin, session_opts}
              ]

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

  defp configured_state_size(config),
    do: with_state_size_limit(config, state_size_limit(config))

  defp ensure_plugin_compiled!(module) do
    Code.ensure_compiled!(module)

    case module.__jido_plugin__() do
      %Jido.Plugin.Manifest{} = manifest ->
        manifest
        |> Map.take([:agent, :agent_server, :persistence, :topology])
        |> Map.values()
        |> Enum.reject(&is_nil/1)
        |> Enum.each(&Code.ensure_compiled!/1)

      _ ->
        :ok
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

  defp route(
         %{
           target:
             {%Jido.Agent.Extension.RouteTarget{
                extension: Jido.AI.DSL,
                option: :ai,
                value: id
              }, defaults}
         } = route,
         flows
       )
       when is_map(defaults) do
    route(%{route | target: {%Ref{id: id}, defaults}}, flows)
  end

  defp route(
         %{
           target: %Jido.Agent.Extension.RouteTarget{
             extension: Jido.AI.DSL,
             option: :ai,
             value: id
           }
         } = route,
         flows
       ) do
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

  defp prefer_explicit_observation_routes(internal, explicit) do
    {:ok, explicit} = Jido.Agent.Authoring.routes(explicit)
    {:ok, router} = Jido.Signal.Router.new(explicit)

    Enum.reject(internal, fn route ->
      Jido.AI.Session.observation_type?(route.path) and
        explicitly_routed?(router, route.path)
    end)
  end

  defp explicitly_routed?(router, type) do
    signal = Jido.Signal.new!(type, %{}, source: "/jido/ai/authoring")
    match?({:ok, [_ | _]}, Jido.Signal.Router.route(router, signal))
  end

  defp flow(%{requests: %{mode: :session}} = profile),
    do: Jido.AI.Session.admission_target(profile)

  defp flow(profile), do: {:ok, {Jido.AI.Runtime.Run, %{profile_id: profile.id}}}

  @doc false
  def reasoning_flow(profile), do: Jido.AI.Runtime.Flow.build(profile)
end
