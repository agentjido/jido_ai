defmodule JidoAI.Examples.StableAoTLifecycleTest do
  # Port of the AoT lifecycle case retained by PRs 231 and 309.
  use ExUnit.Case, async: false
  @moduletag :example
  import JidoAI.Examples.Case
  alias JidoAI.Examples.AoT
  alias Jido.AI.{Observe, Request, Session}

  test "AoT emits request started/completed signals and request telemetry" do
    jido = :"aot_stable_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    id = "aot_lifecycle_#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        id,
        [Observe.request(:start), Observe.request(:complete)],
        &JidoAI.Examples.Linear.Telemetry.handle/4,
        self()
      )

    on_exit(fn -> :telemetry.detach(id) end)

    {mock, context} =
      mock([%{reply: {:stream, [{:wait, :held}, %{content: AoT.puzzle()}], "stop"}}])

    assert {:ok, definition} = AoT.definition()

    assert {:ok, server} =
             Jido.start_agent(jido, Jido.Agent.instantiate!(definition), default_dispatch: {:pid, target: self()})

    assert {:ok, handle} =
             Request.create_and_send(server, "8 6 4 4",
               request_id: "req_aot_lifecycle",
               signal_type: "ai.aot.query",
               source: "/aot",
               context: context
             )

    request_id = handle.id
    assert_receive {:mock_llm_waiting, ^mock, :held, _}, 2_000

    assert_receive {:signal, %{type: "ai.request.started", data: %{request_id: ^request_id}}},
                   2_000

    assert_receive {:linear_telemetry, [:jido, :ai, :request, :start], _, %{request_id: ^request_id, strategy: :aot}},
                   2_000

    # Hold real model work for a measured interval; the reported duration cannot be a zero placeholder.
    Process.send_after(self(), :release_model, 25)
    assert_receive :release_model, 1_000
    JidoAI.Examples.MockLLM.release(mock, :held)
    assert {:ok, result} = Request.await(handle)
    assert result.answer == "(4 + (8 - 6)) * 4 = 24"

    assert_receive {:signal,
                    %{
                      type: "ai.request.completed",
                      data: %{request_id: ^request_id, result: ^result}
                    }},
                   2_000

    assert_receive {:linear_telemetry, [:jido, :ai, :request, :complete], measurements, metadata},
                   2_000

    assert metadata.request_id == request_id and metadata.strategy == :aot
    assert metadata.origin == :worker_runtime
    assert measurements.total_tokens == 15 and measurements.duration_ms >= 25
    assert {:ok, _} = Session.delivery_status(server, request_id)
    assert_script_done(mock)
  end
end
