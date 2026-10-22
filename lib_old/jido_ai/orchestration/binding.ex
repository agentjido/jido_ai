defmodule Jido.AI.Orchestration.Binding do
  @moduledoc false

  def request(%Jido.Agent{routes: routes}, %Jido.Signal{data: data} = signal) when is_map(data) do
    with {:ok, router} <- Jido.Signal.Router.new(routes),
         {:ok, [{target, %{profile_id: id} = defaults}]} <-
           Jido.Signal.Router.route(router, signal),
         true <- target == Jido.AI.Orchestration.Start do
      %{
        id: id,
        input: Map.merge(defaults, data)
      }
    else
      _error -> nil
    end
  end

  def request(_agent, _signal), do: nil

  def method(agent, signal) do
    with %{id: id} <- request(agent, signal),
         {Jido.AI.Configuration.Plugin, opts} <-
           Enum.find(agent.plugins, &(elem(&1, 0) == Jido.AI.Configuration.Plugin)),
         %Jido.AI.Profile{reasoning: %{method: method}} <- opts[:profiles][id] do
      method
    else
      _error -> :unknown
    end
  end
end
