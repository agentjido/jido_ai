defmodule Jido.AI.Agent.Interface do
  @moduledoc false

  def ask(module, server, query, opts) do
    with {:ok, _profile, route} <- request_route(module, opts) do
      Jido.AI.Request.create_and_send(
        server,
        query,
        Keyword.merge(opts, signal_type: route.path, source: "/jido/ai/agent")
      )
    end
  end

  def ask_sync(module, server, query, opts) do
    with {:ok, request} <- ask(module, server, query, opts) do
      Jido.AI.Request.await(request, opts)
    end
  end

  def ask_stream(module, server, query, opts) do
    opts = opts |> Keyword.put(:stream, true) |> Keyword.put(:stream_to, {:pid, self()})

    with {:ok, request} <- ask(module, server, query, opts) do
      {:ok, %{request: request, events: Jido.AI.Request.Stream.events(request, opts)}}
    end
  end

  def cancel(server, opts) do
    data = %{request_id: opts[:request_id], reason: Keyword.get(opts, :reason, :user_cancelled)}
    signal = Jido.Signal.new!(Jido.AI.Orchestration.cancel_type(), data, source: "/jido/ai/agent")
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

          target == Jido.AI.Orchestration.Start and
            is_map(defaults) and defaults[:profile_id] == profile.id
        end)
      end

    if profile && route,
      do: {:ok, profile, route},
      else: Jido.AI.Profile.error("profile", "Select one routed AI profile")
  end
end
