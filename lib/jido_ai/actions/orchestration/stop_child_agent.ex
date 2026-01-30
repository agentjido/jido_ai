defmodule Jido.AI.Actions.Orchestration.StopChildAgent do
  @moduledoc """
  Stop a tracked child agent gracefully.

  This action wraps Jido's `StopChild` directive, providing lifecycle
  control for child agents spawned via `SpawnChildAgent`.

  ## Parameters

  * `tag` (required) - Tag of the child to stop
  * `reason` (optional) - Reason for stopping (default: `:normal`)

  ## Examples

      {:ok, result} = Jido.Exec.run(StopChildAgent, %{
        tag: :worker_1
      })

      # With specific reason
      {:ok, result} = Jido.Exec.run(StopChildAgent, %{
        tag: :processor,
        reason: :shutdown
      })

  ## Result

  Returns a `StopChild` directive that the runtime will execute:

      %{
        directive: %Jido.Agent.Directive.StopChild{...},
        tag: :worker_1
      }
  """

  use Jido.Action,
    name: "stop_child_agent",
    description: "Stop a tracked child agent gracefully",
    category: "orchestration",
    tags: ["orchestration", "multi-agent", "lifecycle"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        tag: Zoi.any(description: "Tag of the child to stop"),
        reason: Zoi.any(description: "Reason for stopping") |> Zoi.default(:normal)
      })

  alias Jido.Agent.Directive

  @impl Jido.Action
  def run(params, _context) do
    directive = %Directive.StopChild{
      tag: params.tag,
      reason: params[:reason] || :normal
    }

    {:ok, %{directive: directive, tag: params.tag}}
  end
end
