defmodule Jido.AI.Test.Requests do
  @moduledoc false

  # Completion assertions must wait for settlement. A core route call returns
  # only the admission revision. Keep this distinction explicit in each test.
  def call_and_await(server, signal, opts \\ []) do
    with {:ok, admitted} <- Jido.AgentServer.call(server, signal, opts) do
      await_agent(server, admitted, opts)
    end
  end

  def await_agent(server, admitted, opts \\ []) do
    case Enum.find(Map.get(admitted.state, :requests, %{}), fn {_, record} -> record.status == :pending end) do
      nil ->
        {:ok, admitted}

      {id, _} ->
        request = Jido.AI.Request.Handle.new(id, server, "")

        with {:ok, _} <- Jido.AI.Request.await(request, timeout: Keyword.get(opts, :timeout, 10_000)) do
          {:ok, Jido.AgentServer.agent(server)}
        end
    end
  end
end
