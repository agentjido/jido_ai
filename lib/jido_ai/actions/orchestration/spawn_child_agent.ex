defmodule Jido.AI.Actions.Orchestration.SpawnChildAgent do
  @moduledoc """
  Spawn a child agent with parent-child hierarchy tracking.

  This action wraps Jido's `SpawnAgent` directive, providing an AI-friendly
  interface for multi-agent orchestration.

  ## Parameters

  * `agent` (required) - Agent module to spawn
  * `tag` (required) - Tag for tracking this child
  * `opts` (optional) - Options passed to child AgentServer
  * `meta` (optional) - Metadata to pass to child

  ## Examples

      {:ok, result} = Jido.Exec.run(SpawnChildAgent, %{
        agent: MyWorkerAgent,
        tag: :worker_1
      })

      # With metadata
      {:ok, result} = Jido.Exec.run(SpawnChildAgent, %{
        agent: MyWorkerAgent,
        tag: :processor,
        meta: %{task_type: "analysis"}
      })

  ## Result

  Returns a `SpawnAgent` directive that the runtime will execute:

      %{
        directive: %Jido.Agent.Directive.SpawnAgent{...},
        tag: :worker_1
      }
  """

  use Jido.Action,
    name: "spawn_child_agent",
    description: "Spawn a child agent with parent-child hierarchy",
    category: "orchestration",
    tags: ["orchestration", "multi-agent", "spawn"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        agent: Zoi.any(description: "Agent module to spawn"),
        tag: Zoi.any(description: "Tag for tracking this child"),
        opts: Zoi.map(description: "Options for child AgentServer") |> Zoi.default(%{}),
        meta: Zoi.map(description: "Metadata to pass to child") |> Zoi.default(%{})
      })

  alias Jido.Agent.Directive

  @impl Jido.Action
  def run(params, _context) do
    directive = %Directive.SpawnAgent{
      agent: params.agent,
      tag: params.tag,
      opts: params[:opts] || %{},
      meta: params[:meta] || %{}
    }

    {:ok, %{directive: directive, tag: params.tag}}
  end
end
