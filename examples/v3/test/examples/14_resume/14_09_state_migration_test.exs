defmodule JidoAI.Examples.StateMigrationTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Context
  alias Jido.AI.Reasoning.ReAct
  alias ReAct.{Config, State, Token, PendingToolCall}
  alias JidoAI.Examples.StateMigration, as: Example
  alias JidoAI.Examples.StandaloneAuthoring.{Add, Change, Transform}

  test "old after-model token restores tools from history before its pending list was filled", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "Five"}}])
    config = config(mock, tools: [Add])
    old = legacy(tool_context(), active_tools: %{"add" => Add})
    assert {:ok, old_state} = State.from_checkpoint_map(old)
    token = legacy_token(old, config)
    assert old_state.pending_tool_calls == []
    assert {:ok, decoded, _} = Token.decode_state(token, config)
    assert decoded.status == :running and decoded.pending_tool_calls == []
    assert {:ok, converted} = State.migrate(decoded, config, evidence(:after_llm, 1, 1, 0))
    assert [%{id: "legacy-tool", status: :pending}] = converted.pending_tool_calls
    assert converted.status == :awaiting_tools
    assert {:ok, result} = Example.resume(old, config, evidence(:after_llm, 1, 1, 0), opts(jido))
    assert result.result == "Five" and result.usage.total_tokens == 30
    assert_receive {:standalone_add, _, 2, 3}
    refute_receive {:standalone_add, _, _, _}, 20
    assert Enum.count(result.trace, &(&1.kind == :llm_started)) == 1
    refute Enum.any?(result.trace, &(&1.kind == :request_started))
    assert hd(result.trace).seq > old.seq
    assert Enum.all?(result.trace, &(&1.run_id == old.run_id && &1.request_id == old.request_id))
    assert {:ok, final, _} = Token.decode_state(result.final_token, config)
    assert final.checkpoint.runtime.model_calls == 2 and final.iteration == 2
    assert old.pending_tool_calls == [] and not Map.has_key?(old, :checkpoint)
    assert_script_done(mock)
  end

  test "old after-tools state uses the supplied committed domain without replaying tools", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "Nine"}}])
    config = config(mock, tools: [Add], request_transformer: Transform)

    old =
      legacy(completed_tools(),
        iteration: 2,
        active_tools: %{"add" => Add},
        prev_tool_signature: "legacy-signature"
      )

    proof = Keyword.put(evidence(:after_tools, 1, 1, 1), :domain, %{count: 9})
    assert {:ok, result} = Example.resume(old, config, proof, opts(jido))
    assert result.result == "Nine" and result.usage.total_tokens == 30
    assert_receive {:standalone_count, 9}
    refute_receive {:standalone_add, _, _, _}, 20
    [wire] = MockLLM.report(mock).requests
    assert Enum.count(wire.body["messages"], &(&1["role"] == "tool")) == 1
    assert {:ok, final, _} = Token.decode_state(result.final_token, config)
    assert final.checkpoint.domain.count == 9 and final.checkpoint.effects == []
    assert final.prev_tool_signature == "legacy-signature"
    assert_script_done(mock)
  end

  test "old final-model checkpoint completes from saved text without a model call", %{jido: jido} do
    {mock, _} = mock([])
    config = config(mock)
    old = legacy(Context.append_assistant(context(), "Saved answer"))
    assert {:ok, result} = Example.resume(old, config, evidence(:after_llm, 1, 1, 0), opts(jido))
    assert result.result == "Saved answer" and result.usage.total_tokens == 15
    refute Enum.any?(result.trace, &(&1.kind == :llm_started))
    assert_script_done(mock)
  end

  test "old final-model checkpoint validates its saved typed answer on the native output path", %{
    jido: jido
  } do
    {mock, _} = mock([])
    config = config(mock, output: %{schema: Zoi.object(%{answer: Zoi.string()})})
    old = legacy(Context.append_assistant(context(), ~s({"answer":"Saved object"})))
    assert {:ok, result} = Example.resume(old, config, evidence(:after_llm, 1, 1, 0), opts(jido))
    assert result.result == %{answer: "Saved object"}
    assert Enum.any?(result.trace, &(&1.kind == :output_validated))
    assert_script_done(mock)
  end

  test "initial old state retains rich input refs and one system message", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "Read"}}])
    model = put_in(MockLLM.model().extra.wire.protocol, "openai_responses")
    config = config(mock, model: model, system_prompt: "Use this file")

    input = [
      ReqLLM.Message.ContentPart.text("Read this"),
      ReqLLM.Message.ContentPart.file_id("file-old", "application/pdf")
    ]

    ctx =
      Context.new(system_prompt: "Use this file")
      |> Context.append_user(input, refs: %{source: "/old/input", document: "old-doc"})

    old = legacy(ctx, seq: 0, usage: %{}, llm_call_id: nil, llm_response_id: nil)
    assert {:ok, result} = Example.resume(old, config, evidence(:before_llm, 0, 0, 0), opts(jido))
    assert result.result == "Read"
    [wire] = MockLLM.report(mock).requests
    assert Enum.count(wire.body["input"], &(&1["role"] == "user")) == 1
    assert Enum.count(wire.body["input"], &(&1["role"] == "system")) == 1
    user = Enum.find(wire.body["input"], &(&1["role"] == "user"))

    assert Enum.any?(
             user["content"],
             &(&1["type"] == "input_file" && &1["file_id"] == "file-old")
           )

    assert {:ok, final, _} = Token.decode_state(result.final_token, config)
    assert Enum.any?(final.context.entries, &(get_in(&1.refs || %{}, [:document]) == "old-doc"))
    assert_script_done(mock)
  end

  test "terminal old state keeps explicit model repair counts when new input is appended", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "Next"}}])
    config = config(mock, max_iterations: 5)

    old =
      legacy(Context.append_assistant(context(), "First"),
        status: :completed,
        result: "First",
        usage: %{total_tokens: 45}
      )

    assert {:ok, state} = State.migrate(old, config, evidence(:terminal, 1, 3, 0))

    result =
      state
      |> ReAct.stream_from_state(config, Keyword.put(opts(jido), :query, "Next query"))
      |> ReAct.collect_stream()

    assert result.result == "Next" and result.usage.total_tokens == 60
    assert {:ok, final, _} = Token.decode_state(result.final_token, config)
    assert final.iteration == 2 and final.checkpoint.runtime.model_calls == 4
    assert_script_done(mock)
  end

  for status <- [:failed, :cancelled] do
    @status status
    test "#{status} old state restarts only from complete history and supplied counters", %{
      jido: jido
    } do
      {mock, _} = mock([%{reply: {:text, "Recovered"}}])
      config = config(mock, tools: [Add])

      old =
        legacy(completed_tools(),
          status: @status,
          iteration: 2,
          active_tools: %{"add" => Add},
          error: :old_failure
        )

      assert {:ok, state} = State.migrate(old, config, evidence(:terminal, 1, 2, 1))
      assert state.status == @status
      token = Token.issue(state, config)

      assert {:ok, next} =
               ReAct.continue(token, config, Keyword.put(opts(jido), :query, "Continue"))

      result = ReAct.collect_stream(next.events)
      assert result.result == "Recovered" and result.usage.total_tokens == 30
      refute_receive {:standalone_add, _, _, _}, 20
      assert {:ok, final, _} = Token.decode_state(result.final_token, config)
      assert final.error == nil and final.checkpoint.runtime.model_calls == 3
      assert final.checkpoint.runtime.tool_calls == 1
      assert_script_done(mock)
    end
  end

  test "old terminal failure before any model can accept new input after explicit conversion", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "First successful call"}}])
    config = config(mock)
    old = legacy(context(), status: :failed, usage: %{}, error: :before_model)
    assert {:ok, state} = State.migrate(old, config, evidence(:terminal, 0, 0, 0))

    result =
      state
      |> ReAct.stream_from_state(config, Keyword.put(opts(jido), :query, "Retry"))
      |> ReAct.collect_stream()

    assert result.result == "First successful call"
    assert_script_done(mock)
  end

  test "conversion retains an exhausted time bound and cannot issue a provider request", %{
    jido: jido
  } do
    {mock, _} = mock([])
    config = config(mock)
    old = legacy(completed_tools(), iteration: 2)
    proof = Keyword.put(evidence(:after_tools, 1, 1, 1), :remaining_ms, 0)
    assert {:ok, result} = Example.resume(old, config, proof, opts(jido))
    assert result.termination_reason == :failed
    assert inspect(result.result) =~ "checkpoint_deadline_exhausted"
    assert_script_done(mock)
  end

  test "converted pending work still uses current tool permissions", %{jido: jido} do
    {mock, _} = mock([])
    config = config(mock, tools: [Add])
    old = legacy(tool_context(), active_tools: %{"add" => Add})

    options =
      Keyword.put(opts(jido), :context, %{
        jido: jido,
        observer: self(),
        __tool_guardrail_callback__: fn _ -> {:error, :revoked} end
      })

    assert {:ok, result} = Example.resume(old, config, evidence(:after_llm, 1, 1, 0), options)
    assert result.termination_reason == :failed and inspect(result.result) =~ "revoked"
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "missing phase counters domain or time evidence returns an error without model work" do
    {mock, _} = mock([])
    config = config(mock)
    proof = evidence(:after_llm, 1, 1, 0)
    old = legacy(Context.append_assistant(context(), "Saved"))

    for key <- [:phase, :counters, :domain, :remaining_ms] do
      assert {:error, {:state_migration, _}} =
               State.migrate(old, config, Keyword.delete(proof, key))
    end

    assert {:error, {:state_migration, _}} =
             State.migrate(old, config, Keyword.put(proof, :unknown, true))

    assert_script_done(mock)
  end

  test "counter evidence cannot undercount saved messages or disagree with the saved position" do
    {mock, _} = mock([])
    config = config(mock)
    old = legacy(completed_tools(), iteration: 2)

    for proof <- [
          evidence(:after_tools, 1, 0, 1),
          evidence(:after_tools, 1, 1, 0),
          evidence(:after_tools, -1, 1, 1),
          evidence(:after_tools, 2, 2, 1)
        ] do
      assert {:error, {:state_migration, _}} = State.migrate(old, config, proof)
    end

    assert_script_done(mock)
  end

  test "unresolved or partial tool work requires reconciliation before restart" do
    {mock, _} = mock([])
    config = config(mock, tools: [Add])
    old = legacy(tool_context(), status: :failed, active_tools: %{"add" => Add})

    assert {:error, {:state_migration, :unresolved_tool_calls}} =
             State.migrate(old, config, evidence(:terminal, 1, 1, 0))

    assert {:error, {:state_migration, :unresolved_tool_calls}} =
             State.migrate(
               %{old | status: :running, iteration: 2},
               config,
               evidence(:before_llm, 1, 1, 0)
             )

    pending = PendingToolCall.from_tool_call(call()) |> Map.put(:attempts, 1)

    assert {:error, {:state_migration, :uncertain_tool_execution}} =
             State.migrate(
               %{old | status: :awaiting_tools, pending_tool_calls: [pending]},
               config,
               evidence(:after_llm, 1, 1, 0)
             )

    assert_script_done(mock)
  end

  test "a changed legacy tool catalog needs an explicit current configuration" do
    {mock, _} = mock([])
    config = config(mock, tools: [Change])
    old = legacy(tool_context(), active_tools: %{"add" => Add})

    assert {:error, {:state_migration, :tool_catalog_changed}} =
             State.migrate(old, config, evidence(:after_llm, 1, 1, 0))

    assert_script_done(mock)
  end

  test "unsupported versions live data and malformed tool history cannot become native tokens" do
    {mock, _} = mock([])
    config = config(mock)
    old = legacy(context(), seq: 0, usage: %{})
    proof = evidence(:before_llm, 0, 0, 0)

    assert {:error, {:state_migration, :unsupported_state_version}} =
             State.migrate(%{old | version: 99}, config, proof)

    assert {:error, {:state_migration, _}} =
             State.migrate(old, config, Keyword.put(proof, :domain, %{pid: self()}))

    assert {:error, {:state_migration, _}} =
             State.migrate(old, config, Keyword.put(proof, :domain, %{messages: []}))

    orphan = Context.append_tool_result(context(), "missing", "add", "5")

    assert {:error, {:state_migration, :invalid_tool_history}} =
             State.migrate(%{old | context: orphan}, config, proof)

    assert_script_done(mock)
  end

  test "string-keyed old maps retain terminal results through token replay", %{jido: jido} do
    {mock, _} = mock([])
    config = config(mock)
    old = legacy(Context.append_assistant(context(), "Keep"), status: :completed, result: "Keep")
    encoded = Map.new(old, fn {key, value} -> {Atom.to_string(key), value} end)
    assert {:ok, state} = State.migrate(encoded, config, evidence(:terminal, 1, 1, 0))
    token = Token.issue(state, config)
    assert {:ok, next} = ReAct.continue(token, config, opts(jido))
    result = ReAct.collect_stream(next.events)
    assert result.result == "Keep"
    assert Enum.map(result.trace, & &1.kind) == [:request_completed, :checkpoint]
    assert_script_done(mock)
  end

  test "native checkpoint data cannot be imported again to replace its binding", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "Native"}}])
    config = config(mock)
    result = ReAct.run("Save", config, opts(jido))
    assert {:ok, state, _} = Token.decode_state(result.final_token, config)

    assert {:error, {:state_migration, :already_native}} =
             State.migrate(state, config, evidence(:terminal, 1, 1, 0))

    assert_script_done(mock)
  end

  test "a real failed model call after tools can restart without repeating completed work", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:tools, [call()]}},
        %{reply: {:error, 400, "model failure after tools"}},
        %{reply: {:text, "Recovered after tools"}}
      ])

    config = config(mock, tools: [Add])
    failed = ReAct.run("Sum", config, opts(jido))
    assert failed.termination_reason == :failed
    assert_receive {:standalone_add, _, 2, 3}
    assert {:ok, state, _} = Token.decode_state(failed.final_token, config)
    assert state.checkpoint == nil
    calls = Enum.count(failed.trace, &(&1.kind == :llm_started))
    tools = Enum.count(failed.trace, &(&1.kind == :tool_completed))
    assert calls == 2 and tools == 1
    assert {:ok, converted} = State.migrate(state, config, evidence(:terminal, 1, calls, tools))

    result =
      converted
      |> ReAct.stream_from_state(config, Keyword.put(opts(jido), :query, "Continue"))
      |> ReAct.collect_stream()

    assert result.result == "Recovered after tools" and result.usage.total_tokens == 30
    refute_receive {:standalone_add, _, _, _}, 20
    assert {:ok, final, _} = Token.decode_state(result.final_token, config)
    assert final.checkpoint.runtime.model_calls == 3 and final.iteration == 2
    assert_script_done(mock)
  end

  test "old maximum-iteration result needs its event reason and retains the exhausted bound", %{
    jido: jido
  } do
    {mock, _} = mock([])
    config = config(mock, max_iterations: 1)

    old =
      legacy(completed_tools(),
        status: :completed,
        iteration: 2,
        result: "Maximum iterations reached without a final answer."
      )

    proof = Keyword.put(evidence(:terminal, 1, 1, 1), :termination_reason, :max_iterations)
    assert {:ok, state} = State.migrate(old, config, proof)
    assert state.iteration == 2 and state.termination_reason == :max_iterations

    result =
      state
      |> ReAct.stream_from_state(config, Keyword.put(opts(jido), :query, "Again"))
      |> ReAct.collect_stream()

    assert result.termination_reason == :max_iterations
    refute Enum.any?(result.trace, &(&1.kind == :llm_started))
    assert_script_done(mock)
  end

  test "extra model calls retained from old repairs still consume the current model bound", %{
    jido: jido
  } do
    {mock, _} = mock([])
    config = config(mock, max_iterations: 2)

    old =
      legacy(Context.append_assistant(context(), "Saved"), status: :completed, result: "Saved")

    assert {:ok, state} = State.migrate(old, config, evidence(:terminal, 1, 2, 0))

    result =
      state
      |> ReAct.stream_from_state(config, Keyword.put(opts(jido), :query, "Again"))
      |> ReAct.collect_stream()

    assert result.termination_reason == :failed
    refute Enum.any?(result.trace, &(&1.kind == :llm_started))
    assert_script_done(mock)
  end

  test "duplicate call IDs wrong tool names and false terminal reasons fail conversion" do
    {mock, _} = mock([])
    config = config(mock, tools: [Add])
    duplicate = Context.append_assistant(context(), "", [call(), call()])
    wrong_name = Context.append_tool_result(tool_context(), "legacy-tool", "changed-name", "5")

    for ctx <- [duplicate, wrong_name] do
      assert {:error, {:state_migration, :invalid_tool_history}} =
               State.migrate(legacy(ctx), config, evidence(:after_llm, 1, 1, 0))
    end

    proof = Keyword.put(evidence(:after_llm, 1, 1, 0), :termination_reason, :max_iterations)

    assert {:error, {:state_migration, :invalid_termination_reason}} =
             State.migrate(legacy(tool_context()), config, proof)

    assert_script_done(mock)
  end

  defp legacy_token(old, config) do
    payload = %{
      v: 2,
      iss: "jido_ai/react",
      run_id: old.run_id,
      request_id: old.request_id,
      iat_ms: System.system_time(:millisecond),
      exp_ms: nil,
      config_fingerprint: Config.fingerprint(config),
      state: old
    }

    bytes = :erlang.term_to_binary(payload)
    signature = :crypto.mac(:hmac, :sha256, config.token.secret, bytes)

    "rt2." <>
      Base.url_encode64(bytes, padding: false) <>
      "." <> Base.url_encode64(signature, padding: false)
  end

  # This map is the released State-v3 shape, before native checkpoint fields.
  # The v2 Runner emits after_llm before it fills pending_tool_calls.
  defp legacy(context, extra \\ []) do
    Map.merge(
      %{
        version: 3,
        request_id: "legacy-request",
        run_id: "legacy-run",
        status: :running,
        iteration: 1,
        seq: 7,
        llm_call_id: "legacy-call",
        llm_response_id: "legacy-response",
        context: context,
        active_tools: %{},
        pending_tool_calls: [],
        usage: %{total_tokens: 15},
        output: %{},
        streaming_text: "",
        streaming_thinking: "",
        result: nil,
        error: nil,
        started_at_ms: 1_788_694_000_000,
        updated_at_ms: 1_788_694_000_010,
        prev_tool_signature: nil
      },
      Map.new(extra)
    )
  end

  defp evidence(phase, iterations, model_calls, tool_calls),
    do: [
      phase: phase,
      counters: %{iterations: iterations, model_calls: model_calls, tool_calls: tool_calls},
      domain: %{},
      remaining_ms: 5_000
    ]

  defp context, do: Context.new(system_prompt: "Use saved history") |> Context.append_user("Sum")
  defp call, do: %{id: "legacy-tool", name: "add", arguments: %{a: 2, b: 3}}
  defp tool_context, do: Context.append_assistant(context(), "", [call()])

  defp completed_tools,
    do: Context.append_tool_result(tool_context(), "legacy-tool", "add", ~s({"sum":5}))

  defp config(mock, extra \\ []),
    do:
      Config.new(
        Keyword.merge(
          [
            model: MockLLM.model(),
            tools: [],
            streaming: false,
            token_secret: "state-migration-case",
            llm_opts: MockLLM.options(mock)
          ],
          extra
        )
      )

  defp opts(jido),
    do: [context: %{jido: jido, observer: self()}, limits: %{timeout: 5_000, max_tool_calls: 32}]
end
