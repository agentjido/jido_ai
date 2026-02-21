defmodule Jido.AI.Integration.RequestAwaitRejectionTest do
  use ExUnit.Case, async: false
  use Mimic

  defmodule CoTAwaitAgent do
    use Jido.AI.CoTAgent, name: "cot_await_agent", model: "test:model"
  end

  defmodule ToTAwaitAgent do
    use Jido.AI.ToTAgent, name: "tot_await_agent", model: "test:model"
  end

  defmodule GoTAwaitAgent do
    use Jido.AI.GoTAgent, name: "got_await_agent", model: "test:model"
  end

  defmodule TRMAwaitAgent do
    use Jido.AI.TRMAgent, name: "trm_await_agent", model: "test:model"
  end

  defmodule AdaptiveAwaitAgent do
    use Jido.AI.AdaptiveAgent,
      name: "adaptive_await_agent",
      model: "test:model",
      default_strategy: :cot,
      available_strategies: [:cot]
  end

  setup :set_mimic_from_context

  setup do
    if is_nil(Process.whereis(Jido.Registry)) do
      start_supervised!({Registry, keys: :unique, name: Jido.Registry})
    end

    if is_nil(Process.whereis(Jido.AgentSupervisor)) do
      start_supervised!({DynamicSupervisor, strategy: :one_for_one, name: Jido.AgentSupervisor})
    end

    if is_nil(Process.whereis(Jido.TaskSupervisor)) do
      start_supervised!({Task.Supervisor, name: Jido.TaskSupervisor})
    end

    # Keep first request active long enough so the second request reliably hits
    # the strategy busy-rejection path before completion.
    Mimic.stub(ReqLLM.Generation, :generate_text, fn _model, _messages, _opts ->
      Process.sleep(150)

      {:ok,
       %{
         message: %{content: "ok", tool_calls: nil},
         finish_reason: :stop,
         usage: %{input_tokens: 1, output_tokens: 1}
       }}
    end)

    Mimic.stub(ReqLLM.Generation, :stream_text, fn _model, _messages, _opts ->
      Process.sleep(150)
      {:ok, %{stream: [ReqLLM.StreamChunk.text("ok")], usage: %{input_tokens: 1, output_tokens: 1}}}
    end)

    Mimic.stub(ReqLLM.StreamResponse, :usage, fn
      %{usage: usage} -> usage
      _ -> nil
    end)

    :ok
  end

  describe "Request.await/2 for second concurrent requests" do
    test "CoT returns rejected busy error" do
      assert_rejected_busy(CoTAwaitAgent, :think)
    end

    test "ToT returns rejected busy error" do
      assert_rejected_busy(ToTAwaitAgent, :explore)
    end

    test "GoT returns rejected busy error" do
      assert_rejected_busy(GoTAwaitAgent, :explore)
    end

    test "TRM returns rejected busy error" do
      assert_rejected_busy(TRMAwaitAgent, :reason)
    end

    test "Adaptive returns rejected busy error" do
      assert_rejected_busy(AdaptiveAwaitAgent, :ask)
    end
  end

  defp assert_rejected_busy(agent_module, request_fn) do
    {:ok, pid} = Jido.AgentServer.start_link(agent: agent_module)
    on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)

    {:ok, _first_request} = apply(agent_module, request_fn, [pid, "first request"])
    {:ok, second_request} = apply(agent_module, request_fn, [pid, "second request"])

    assert {:error, {:rejected, :busy, _message}} = agent_module.await(second_request, timeout: 1_000)
  end
end
