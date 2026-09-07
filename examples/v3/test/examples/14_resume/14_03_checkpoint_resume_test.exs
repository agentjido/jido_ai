defmodule JidoAI.Examples.CheckpointResumeTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Reasoning.ReAct
  alias ReAct.{Config, Token}
  alias JidoAI.Examples.CheckpointResume, as: Example
  alias JidoAI.Examples.CheckpointResume.Reloadable
  alias JidoAI.Examples.StandaloneAuthoring.{Add, Change, Transform, Repair}

  test "after-model checkpoint stops before tool work and resumes without another model call", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "once", name: "add", arguments: %{a: 2, b: 3}}]}},
        %{reply: {:text, "Five"}}
      ])

    config = config(mock, tools: [Add])
    events = ReAct.stream("Sum", config, opts(jido)) |> Example.through_checkpoint(:after_llm)
    checkpoint = List.last(events)

    assert checkpoint.kind == :checkpoint and checkpoint.data.reason == :after_llm,
           inspect(Enum.map(events, &{&1.kind, &1.data[:error]}), limit: :infinity)

    refute_receive {:standalone_add, _, _, _}, 20
    assert length(MockLLM.report(mock).requests) == 1
    assert {:ok, saved, _} = Token.decode_state(checkpoint.data.token, config)
    assert saved.status == :awaiting_tools
    refute Map.has_key?(saved.checkpoint.domain, Jido.AI.Context.Operations.key())
    assert [%{id: "once", status: :pending}] = saved.pending_tool_calls
    assert :ok = Jido.Action.validate_static_data(saved)
    assert {:ok, continued} = ReAct.continue(checkpoint.data.token, config, opts(jido))
    result = ReAct.collect_stream(continued.events)
    assert result.result == "Five" and result.usage.total_tokens == 30
    assert_receive {:standalone_add, _, 2, 3}
    refute_receive {:standalone_add, _, _, _}, 20
    assert hd(result.trace).seq > checkpoint.seq

    assert Enum.all?(
             result.trace,
             &(&1.request_id == checkpoint.request_id and &1.run_id == checkpoint.run_id)
           )

    assert_script_done(mock)
  end

  test "after-tools checkpoint preserves completed tool history and does not repeat its side effect",
       %{jido: jido} do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "completed", name: "add", arguments: %{a: 3, b: 4}}]}},
        %{reply: {:text, "Seven"}}
      ])

    config = config(mock, tools: [Add])
    events = ReAct.stream("Sum", config, opts(jido)) |> Example.through_checkpoint(:after_tools)
    assert_receive {:standalone_add, _, 3, 4}
    checkpoint = List.last(events)
    assert checkpoint.data.reason == :after_tools
    assert length(MockLLM.report(mock).requests) == 1
    assert {:ok, saved, _} = Token.decode_state(checkpoint.data.token, config)
    assert saved.pending_tool_calls == []
    assert {:ok, continued} = ReAct.continue(checkpoint.data.token, config, opts(jido))
    result = ReAct.collect_stream(continued.events)
    assert result.result == "Seven" and result.usage.total_tokens == 30
    refute_receive {:standalone_add, _, _, _}, 20
    [_, wire] = MockLLM.report(mock).requests

    assert Enum.count(
             wire.body["messages"],
             &(&1["role"] == "tool" and &1["tool_call_id"] == "completed")
           ) == 1

    assert {:ok, final, _} = Token.decode_state(result.final_token, config)
    refute Map.has_key?(final.checkpoint.domain, Jido.AI.Context.Operations.key())
    assert Enum.count(final.context.entries, &(&1.role == :user)) == 1
    assert_script_done(mock)
  end

  test "a final-answer model checkpoint resumes to completion with no provider replay", %{
    jido: jido
  } do
    {mock, _} = mock([%{reply: {:text, "Saved answer"}}])
    config = config(mock)
    events = ReAct.stream("Answer", config, opts(jido)) |> Example.through_checkpoint(:after_llm)
    assert List.last(events).data.reason == :after_llm
    assert {:ok, continued} = ReAct.continue(List.last(events).data.token, config, opts(jido))
    result = ReAct.collect_stream(continued.events)
    assert result.result == "Saved answer" and result.usage.total_tokens == 15
    refute Enum.any?(result.trace, &(&1.kind == :llm_started))
    assert_script_done(mock)
  end

  test "saved proposed domain state reaches the next transformer in another process", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "change", name: "change", arguments: %{count: 9}}]}},
        %{reply: {:text, "Nine"}}
      ])

    config = config(mock, tools: [Change], request_transformer: Transform)
    options = opts(jido, context: %{jido: jido, observer: self(), state: %{count: 0}})
    events = ReAct.stream("Change", config, options) |> Example.through_checkpoint(:after_tools)
    assert List.last(events).data.reason == :after_tools
    assert_receive {:standalone_count, 0}
    token = List.last(events).data.token

    task =
      Task.async(fn ->
        {:ok, continued} = ReAct.continue(token, config, options)
        ReAct.collect_stream(continued.events)
      end)

    assert Task.await(task, 5_000).result == "Nine"
    assert_receive {:standalone_count, 9}
    assert_script_done(mock)
  end

  test "resume binds a new local transport without saving credentials or callback handles", %{
    jido: jido
  } do
    {first, _} =
      mock([%{reply: {:tools, [%{id: "transport", name: "add", arguments: %{a: 1, b: 2}}]}}])

    config = config(first, tools: [Add], llm_opts: [api_key: "old-runtime-only-key"])
    events = ReAct.stream("Rebind", config, opts(jido)) |> Example.through_checkpoint(:after_llm)
    token = List.last(events).data.token
    assert {:ok, payload} = Token.decode(token, config)
    refute inspect(payload, limit: :infinity) =~ "old-runtime-only-key"
    # A second instance of the same shared mock represents the rebound endpoint.
    second =
      start_supervised!({MockLLM, script: [%{reply: {:text, "Rebound"}}], observer: self()},
        id: :rebound_mock
      )

    next_config = config(second, tools: [Add], llm_opts: [api_key: "new-runtime-only-key"])
    assert {:ok, continued} = ReAct.continue(token, next_config, opts(jido))
    assert ReAct.collect_stream(continued.events).result == "Rebound"
    assert_receive {:standalone_add, _, 1, 2}
    assert_script_done(first)
    assert_script_done(second)
  end

  test "current tool permission is checked again before a resumed pending tool", %{jido: jido} do
    {mock, _} =
      mock([%{reply: {:tools, [%{id: "denied", name: "add", arguments: %{a: 1, b: 2}}]}}])

    config = config(mock, tools: [Add])

    events =
      ReAct.stream("Permission", config, opts(jido)) |> Example.through_checkpoint(:after_llm)

    assert List.last(events).data.reason == :after_llm

    context = %{
      jido: jido,
      observer: self(),
      __tool_guardrail_callback__: fn _ -> {:error, :permission_removed} end
    }

    assert {:ok, continued} =
             ReAct.continue(List.last(events).data.token, config, opts(jido, context: context))

    result = ReAct.collect_stream(continued.events)
    assert result.termination_reason == :failed
    assert inspect(result.result) =~ "permission_removed"
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "saved counts still stop the model after the permitted tool round", %{jido: jido} do
    {mock, _} =
      mock([%{reply: {:tools, [%{id: "bounded", name: "add", arguments: %{a: 1, b: 2}}]}}])

    config = config(mock, tools: [Add], max_iterations: 1)
    events = ReAct.stream("Bound", config, opts(jido)) |> Example.through_checkpoint(:after_tools)
    assert List.last(events).data.reason == :after_tools
    assert_receive {:standalone_add, _, 1, 2}
    assert {:ok, continued} = ReAct.continue(List.last(events).data.token, config, opts(jido))
    result = ReAct.collect_stream(continued.events)
    assert result.termination_reason == :max_iterations
    assert result.usage.total_tokens == 15
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "typed output is validated and repaired after resuming a saved model answer", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "not JSON"}}])

    config =
      config(mock,
        output: [
          schema: Zoi.object(%{answer: Zoi.string()}),
          retries: 1,
          repair_fun: {Repair, :fix}
        ]
      )

    events = ReAct.stream("Typed", config, opts(jido)) |> Example.through_checkpoint(:after_llm)
    assert List.last(events).data.reason == :after_llm
    refute_receive :standalone_repair, 20
    assert {:ok, continued} = ReAct.continue(List.last(events).data.token, config, opts(jido))
    result = ReAct.collect_stream(continued.events)
    assert result.result == %{answer: "Repaired"}
    assert_receive :standalone_repair
    assert_script_done(mock)
  end

  test "a replacement tool with the same alias cannot resume a saved pending call", %{jido: jido} do
    {mock, _} =
      mock([%{reply: {:tools, [%{id: "bound-target", name: "work", arguments: %{a: 1, b: 2}}]}}])

    config = config(mock, tools: %{"work" => Add})
    events = ReAct.stream("Bind", config, opts(jido)) |> Example.through_checkpoint(:after_llm)
    replacement = config(mock, tools: %{"work" => Change})
    assert Config.fingerprint(config) == Config.fingerprint(replacement)

    assert {:ok, continued} =
             ReAct.continue(List.last(events).data.token, replacement, opts(jido))

    result = ReAct.collect_stream(continued.events)
    assert result.termination_reason == :failed
    assert inspect(result.result) =~ "checkpoint_code_or_contract_changed"
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "cancelled intermediate tokens cannot execute the pending tool", %{jido: jido} do
    {mock, _} =
      mock([%{reply: {:tools, [%{id: "cancelled", name: "add", arguments: %{a: 1, b: 2}}]}}])

    config = config(mock, tools: [Add])
    events = ReAct.stream("Cancel", config, opts(jido)) |> Example.through_checkpoint(:after_llm)
    assert {:ok, token} = ReAct.cancel(List.last(events).data.token, config, :user_cancel)
    assert {:ok, continued} = ReAct.continue(token, config, opts(jido))
    assert ReAct.collect_stream(continued.events).termination_reason == :cancelled
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "signed malformed phase data is rejected before runtime admission", %{jido: jido} do
    {mock, _} = mock([%{reply: {:text, "Saved"}}])
    config = config(mock)

    events =
      ReAct.stream("Validate", config, opts(jido)) |> Example.through_checkpoint(:after_llm)

    assert {:ok, payload} = Token.decode(List.last(events).data.token, config)
    original = payload.state.checkpoint

    for changed <- [
          %{original | version: 99},
          %{original | phase: :unknown},
          %{original | remaining_ms: -1},
          put_in(original.runtime.model_calls, -1),
          %{
            original
            | runtime:
                Map.put(original.runtime, :pending_queries, [
                  %{role: :assistant, content: "forged"}
                ])
          },
          %{original | runtime: Map.put(original.runtime, :options, api_key: "must-not-restore")}
        ] do
      invalid = %{payload | state: %{payload.state | checkpoint: changed}}
      assert {:error, :invalid_react_checkpoint} = Token.decode(forge(invalid, config), config)
    end

    assert_script_done(mock)
  end

  test "a lower resumed tool bound is enforced before any saved pending call starts", %{
    jido: jido
  } do
    calls = for id <- ["one", "two"], do: %{id: id, name: "add", arguments: %{a: 1, b: 2}}
    {mock, _} = mock([%{reply: {:tools, calls}}])
    config = config(mock, tools: [Add])
    events = ReAct.stream("Limit", config, opts(jido)) |> Example.through_checkpoint(:after_llm)

    assert {:ok, continued} =
             ReAct.continue(
               List.last(events).data.token,
               config,
               opts(jido, limits: %{timeout: 5_000, max_tool_calls: 1})
             )

    result = ReAct.collect_stream(continued.events)
    assert result.termination_reason == :failed
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  @tag timeout: 30_000
  test "a new operating-system VM resumes completed tool data without another tool execution", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "fresh-vm", name: "add", arguments: %{a: 8, b: 1}}]}},
        %{reply: {:text, "Fresh VM answer"}}
      ])

    config = config(mock, tools: [Add])
    events = ReAct.stream("Fresh", config, opts(jido)) |> Example.through_checkpoint(:after_tools)
    assert List.last(events).data.reason == :after_tools
    assert_receive {:standalone_add, _, 8, 1}

    directory =
      Path.join(System.tmp_dir!(), "jido-ai-checkpoint-#{System.unique_integer([:positive])}")

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    token_path = Path.join(directory, "checkpoint.token")
    File.write!(token_path, List.last(events).data.token)

    script =
      Path.expand(
        "../../../lib/examples/14_resume/14_03_checkpoint_resume/resume_vm.exs",
        __DIR__
      )

    paths = Enum.flat_map(:code.get_path(), fn path -> ["-pa", List.to_string(path)] end)

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["--erl", "+S 2:2"] ++ paths ++ [script, token_path, MockLLM.options(mock)[:base_url]],
        stderr_to_stdout: true
      )

    assert status == 0, output
    line = output |> String.split("\n") |> Enum.find(&String.starts_with?(&1, "CHECKPOINT_VM:"))
    assert is_binary(line), output
    result = line |> String.replace_prefix("CHECKPOINT_VM:", "") |> Jason.decode!()
    assert result["result"] == "Fresh VM answer"
    assert result["usage"]["total_tokens"] == 30
    refute "tool_started" in result["kinds"]
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "changed code under the same tool module cannot resume old pending work", %{jido: jido} do
    {mock, _} = mock([%{reply: {:tools, [%{id: "reload", name: "reloadable", arguments: %{}}]}}])
    config = config(mock, tools: [Reloadable])
    events = ReAct.stream("Code", config, opts(jido)) |> Example.through_checkpoint(:after_llm)
    assert List.last(events).data.reason == :after_llm
    {Reloadable, original, filename} = :code.get_object_code(Reloadable)
    original_options = Code.compiler_options()

    try do
      Code.compiler_options(ignore_module_conflict: true)

      Code.compile_quoted(
        quote do
          defmodule unquote(Reloadable) do
            use Jido.Action,
              name: "reloadable",
              description: "A tool with a checked code identity",
              schema: Zoi.object(%{})

            def run(_, _), do: {:ok, %{version: 2}}
          end
        end
      )

      assert {:ok, continued} = ReAct.continue(List.last(events).data.token, config, opts(jido))
      result = ReAct.collect_stream(continued.events)
      assert result.termination_reason == :failed
      assert inspect(result.result) =~ "checkpoint_code_or_contract_changed"
      assert_script_done(mock)
    after
      Code.compiler_options(original_options)
      :code.purge(Reloadable)
      {:module, Reloadable} = :code.load_binary(Reloadable, filename, original)
    end
  end

  test "a saved repair-model response keeps validation metadata and does not repeat the repair call",
       %{jido: jido} do
    {mock, _} =
      mock([
        %{reply: {:text, "Invalid first answer"}},
        %{reply: {:object, %{answer: "Valid repair"}}}
      ])

    config = config(mock, output: [schema: Zoi.object(%{answer: Zoi.string()}), retries: 1])

    events =
      ReAct.stream("Repair twice", config, opts(jido))
      |> Example.through_checkpoint(:after_llm, 2)

    assert List.last(events).data.reason == :after_llm
    assert {:ok, continued} = ReAct.continue(List.last(events).data.token, config, opts(jido))
    result = ReAct.collect_stream(continued.events)
    assert result.result == %{answer: "Valid repair"}
    assert result.usage.total_tokens == 30
    assert {:ok, state, _} = Token.decode_state(result.final_token, config)
    assert state.output.status == :repaired
    refute Enum.any?(result.trace, &(&1.kind == :llm_started))
    assert_script_done(mock)
  end

  test "an exhausted saved deadline refuses pending work even with a larger new timeout", %{
    jido: jido
  } do
    {mock, _} =
      mock([%{reply: {:tools, [%{id: "expired-budget", name: "add", arguments: %{a: 1, b: 2}}]}}])

    config = config(mock, tools: [Add])
    events = ReAct.stream("Time", config, opts(jido)) |> Example.through_checkpoint(:after_llm)
    assert {:ok, saved, _} = Token.decode_state(List.last(events).data.token, config)
    exhausted = put_in(saved.checkpoint.remaining_ms, 0)
    token = Token.issue(exhausted, config)

    assert {:ok, continued} =
             ReAct.continue(
               token,
               config,
               opts(jido, limits: %{timeout: 60_000, max_tool_calls: 32})
             )

    result = ReAct.collect_stream(continued.events)
    assert result.termination_reason == :failed
    assert inspect(result.result) =~ "checkpoint_deadline_exhausted"
    refute_receive {:standalone_add, _, _, _}, 20
    assert_script_done(mock)
  end

  test "checkpoint expiry does not stop the current live Flow", %{jido: jido} do
    {mock, _} =
      mock([
        %{reply: {:tools, [%{id: "short-ttl", name: "add", arguments: %{a: 2, b: 4}}]}},
        %{reply: {:text, "Six"}}
      ])

    config = config(mock, tools: [Add], token_ttl_ms: 1)
    result = ReAct.run("Sum", config, opts(jido))
    assert result.result == "Six"
    assert result.termination_reason == :final_answer
    assert_receive {:standalone_add, _, 2, 4}
    refute_receive {:standalone_add, _, _, _}, 20
    checkpoint = Enum.find(result.trace, &(&1.kind == :checkpoint))
    Process.sleep(2)
    assert {:error, :token_expired} = Token.decode(checkpoint.data.token, config)
    assert_script_done(mock)
  end

  defp forge(payload, config) do
    bytes = :erlang.term_to_binary(payload)
    signature = :crypto.mac(:hmac, :sha256, config.token.secret, bytes)

    "rt2." <>
      Base.url_encode64(bytes, padding: false) <>
      "." <> Base.url_encode64(signature, padding: false)
  end

  defp config(mock, extra \\ []) do
    options = Keyword.merge(MockLLM.options(mock), Keyword.get(extra, :llm_opts, []))
    assert URI.parse(options[:base_url]).host == "127.0.0.1"

    Config.new(
      Keyword.merge(
        [
          model: MockLLM.model(),
          streaming: false,
          tools: [],
          token_secret: "checkpoint-resume-fixture"
        ],
        extra
      )
      |> Keyword.put(:llm_opts, options)
    )
  end

  defp opts(jido, extra \\ []),
    do:
      Keyword.merge(
        [context: %{jido: jido, observer: self()}, limits: %{timeout: 5_000, max_tool_calls: 32}],
        extra
      )
end
