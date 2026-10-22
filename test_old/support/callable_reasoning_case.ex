defmodule Jido.AI.Test.CallableReasoningCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  alias Jido.AI.Configuration
  alias Jido.AI.Reasoning
  alias Jido.AI.Orchestration
  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias Jido.AI.Test.MockLLM
  alias Jido.AgentServer

  using do
    quote do
      import Jido.AI.Test.CallableReasoningCase
      alias Jido.AI.Test.MockLLM
    end
  end

  setup do
    jido = :"callable_reasoning_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  # The HTTP barrier holds the first call while public APIs identify its owners.
  # No runtime function is stubbed. Both owners must stop before the Action returns.
  def call(jido, profile, prompt, [first | rest], expected_budget, context \\ %{}) do
    first = %{first | reply: {:wait, :started, first.reply}}
    mock = start_supervised!({MockLLM, script: [first | rest], observer: self()})
    options = MockLLM.options(mock)

    context =
      Map.merge(context, %{jido: jido, jido_ai_callable_profile: profile, ai: %{profile.id => %{options: options}}})

    params = %{prompt: prompt}

    task = Task.async(fn -> Jido.Exec.run(RunStrategy, params, context, timeout: 15_000) end)
    assert_receive {:mock_llm_waiting, ^mock, :started, provider}, 5_000
    [{_id, server}] = Jido.list_agents(jido)
    session = AgentServer.children(server)[{:plugin, Orchestration.Plugin}].pid
    monitors = for pid <- [server, session, provider], do: {Process.monitor(pid), pid}

    {:ok, profile} = Configuration.profile(AgentServer.agent(server), profile.id)
    {:ok, selected, selection} = Reasoning.select(profile, params.prompt)
    assert selected.controls.max_model_calls == expected_budget
    assert selected.controls.max_iterations == expected_budget

    :ok = MockLLM.release(mock, :started)
    outcome = Task.await(task, 15_000)

    for {ref, pid} <- monitors do
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
    end

    assert Jido.list_agents(jido) == []
    report = MockLLM.report(mock)
    assert %{remaining: [], unexpected: [], waiting: []} = report

    # A response can reach the client before the HTTP worker sends DOWN.
    # Monitor any such worker instead of polling or sleeping.
    for pid <- report.workers do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5_000
    end

    assert length(report.requests) <= expected_budget
    {outcome, report.requests, selection}
  end

  # Canonical policy for finite HTTP fixtures. Callers supply Profile fields only.
  def callable_profile(method, attrs \\ %{}) do
    defaults = %{
      id: :review,
      model: MockLLM.model(),
      reasoning: %{method: method, options: %{}},
      controls: %{
        timeout: 10_000,
        max_iterations: :method_default,
        max_model_calls: :method_default,
        max_tool_calls: :method_default
      },
      result: %{into: :answer}
    }

    Jido.AI.Profile.new!(Map.merge(defaults, attrs))
  end

  def text_reply(text), do: %{reply: {:text, text}}

  def script(:cod), do: [text_reply("Step 1: Add two and two.\n#### Four")]
  def script(:cot), do: [text_reply("Step 1: Add two and two.\nConclusion: Four")]
  def script(:react), do: [text_reply("Four")]

  def script(:aot) do
    [
      text_reply("""
      Backtracking the solution:
      Step 1: 8 - 6 = 2
      Step 2: 4 + 2 = 6
      Step 3: 6 * 4 = 24
      answer: (4 + (8 - 6)) * 4 = 24
      """)
    ]
  end

  def script(:tot) do
    [
      text_reply(Jason.encode!(%{thoughts: ["First path", "Better path"]})),
      text_reply(Jason.encode!(%{scores: %{t1: 0.4, t2: 0.8}}))
    ]
  end

  def script(:got),
    do: Enum.map(["First analysis", "Refined analysis", "Combined conclusion"], &text_reply/1)

  def script(:trm), do: trm_cycle("First answer", 0.95, "Improved answer")

  def trm_cycle(answer, score, improvement) do
    Enum.map(
      [answer, "SCORE: #{score}\nISSUE: Missing detail\nSUGGESTION: Add detail", improvement],
      &text_reply/1
    )
  end

  def five_trm_cycles do
    Enum.flat_map(Enum.with_index([0.1, 0.3, 0.5, 0.7, 0.8], 1), fn {score, n} ->
      trm_cycle("Analysis #{n}", score, "Improvement #{n}")
    end)
  end

  def assert_success(payload, strategy, method, calls, termination) do
    assert payload.strategy == strategy
    assert payload.status == :success
    assert payload.usage.total_tokens == calls * 15
    assert payload.diagnostics.snapshot_done
    assert payload.diagnostics.snapshot_status == :success
    refute Map.has_key?(payload.diagnostics, :error)
    refute Map.has_key?(payload.diagnostics, :recovered_error)
    details = payload.diagnostics.snapshot_details
    assert details.model_calls == calls
    assert details.termination_reason == termination
    assert details.method == method
    details
  end
end
