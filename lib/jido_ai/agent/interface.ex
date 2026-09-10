defmodule Jido.AI.Agent.Interface do
  @moduledoc false

  def ask(module, server, query, opts) do
    with {:ok, profile, route} <- request_route(module, opts) do
      case profile.requests.mode do
        :session ->
          Jido.AI.Request.create_and_send(
            server,
            query,
            Keyword.merge(opts, signal_type: route.path, source: "/jido/ai/agent")
          )

        :turn ->
          signal = Jido.Signal.new!(route.path, %{query: query}, source: "/jido/ai/agent")

          with {:ok, agent} <-
                 Jido.AgentServer.call(server, signal, timeout: opts[:timeout] || 30_000) do
            {:ok, Map.fetch!(agent.state, profile.result.into)}
          end
      end
    end
  end

  def ask_sync(module, server, query, opts) do
    with {:ok, profile, _route} <- request_route(module, opts),
         {:ok, result} <- ask(module, server, query, opts) do
      if profile.requests.mode == :session,
        do: Jido.AI.Request.await(result, opts),
        else: {:ok, result}
    end
  end

  def ask_stream(module, server, query, opts) do
    with {:ok, profile, _route} <- request_route(module, opts),
         true <- profile.requests.mode == :session and profile.requests.streaming,
         {:ok, request} <- ask(module, server, query, Keyword.put(opts, :stream_to, {:pid, self()})) do
      {:ok, %{request: request, events: Jido.AI.Request.Stream.events(request, opts)}}
    else
      false -> Jido.AI.Profile.error("requests.streaming", "Select a streaming session profile")
      error -> error
    end
  end

  def cancel(server, opts) do
    data = %{request_id: opts[:request_id], reason: Keyword.get(opts, :reason, :user_cancelled)}
    signal = Jido.Signal.new!(Jido.AI.Session.cancel_type(), data, source: "/jido/ai/agent")
    Jido.AgentServer.cast(server, signal)
  end

  defp request_route(module, opts) do
    profiles = Jido.AI.Agent.profiles(module)
    id = opts[:profile]

    profile =
      cond do
        not is_nil(id) -> Map.get(profiles, id)
        map_size(profiles) == 1 -> profiles |> Map.values() |> hd()
        true -> nil
      end

    route =
      if profile do
        Enum.find(module.routes(), fn route ->
          {target, defaults} = Jido.Agent.Authoring.split_target(route.target)

          target in [Jido.AI.Runtime.Run, Jido.AI.Session.Start] and
            is_map(defaults) and defaults[:profile_id] == profile.id
        end)
      end

    if profile && route,
      do: {:ok, profile, route},
      else: Jido.AI.Profile.error("profile", "Select one routed AI profile")
  end
end
