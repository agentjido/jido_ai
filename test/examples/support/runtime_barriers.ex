# Test-only observers and barriers. Tests monitor cancellation or release each barrier.
defmodule JidoAI.Examples.AIRuntime.Record do
  @moduledoc "Records a control call without changing work input."
  @behaviour Jido.AI.Control
  def check(value, context) do
    send(context.observer, {:control_checked, value})
    :ok
  end
end

defmodule JidoAI.Examples.AIRuntime.Reject do
  @moduledoc false
  @behaviour Jido.AI.Control
  def check(_, _), do: Jido.AI.Profile.error("example.policy", "Rejected")
end

defmodule JidoAI.Examples.AIRuntime.WaitTool do
  @moduledoc "A tool with a test-controlled completion barrier."
  use Jido.Action, name: "ai_example_wait", schema: Zoi.object(%{n: Zoi.integer()}, coerce: true)

  def run(%{n: n}, context) do
    send(context.observer, {:tool_waiting, self(), n})

    receive do
      :release -> {:ok, %{value: n}}
    end
  end
end

defmodule JidoAI.Examples.AIRuntime.WaitControl do
  @moduledoc false
  @behaviour Jido.AI.Control
  def check(_, context) do
    send(context.observer, {:control_waiting, self()})

    receive do
      :release -> :ok
    end
  end
end

defmodule JidoAI.Examples.Session.ObserveOwner do
  @moduledoc "Exposes the resource owner to the example's failure checks."
  @behaviour Jido.AI.Control
  def check(_, context) do
    {owner, id, _} = context.jido_ai_events
    send(context.observer, {:session_owner, owner, id})
    :ok
  end
end

defmodule JidoAI.Examples.Steering.ObserveQueue do
  @moduledoc "Exposes the owned queue for failure checks."
  @behaviour Jido.AI.Control
  def check(_, context) do
    send(context.observer, {:input_queue, context.jido_ai_input_queue})
    :ok
  end
end
