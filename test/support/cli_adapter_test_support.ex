defmodule Jido.AI.TestSupport.CLIAdapter do
  @moduledoc false

  alias Jido.Agent.Strategy.Snapshot
  alias Jido.AgentServer.Status

  def status(opts \\ []) do
    %Status{
      agent_module: Keyword.get(opts, :agent_module, __MODULE__),
      agent_id: Keyword.get(opts, :agent_id, "test-agent"),
      pid: Keyword.get(opts, :pid, self()),
      snapshot: %Snapshot{
        status: Keyword.get(opts, :snapshot_status, :success),
        done?: Keyword.get(opts, :done?, true),
        result: Keyword.get(opts, :result),
        details: Keyword.get(opts, :details, %{})
      },
      raw_state: Keyword.get(opts, :raw_state, %{})
    }
  end
end
