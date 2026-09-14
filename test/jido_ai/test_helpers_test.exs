defmodule Jido.AI.TestHelpersTest do
  use Jido.AI.TestCase, async: false

  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Test.ReActScript

  defmodule ReadTool do
    use Jido.Action,
      name: "read",
      description: "Reads a test path",
      schema:
        Zoi.object(%{
          path: Zoi.string()
        })

    def run(%{path: path}, _context), do: {:ok, %{body: "hello from #{path}"}}
  end

  defmodule EchoAgent do
    use Jido.AI.Agent, name: "test_echo_agent", description: "Agent used by public test helper tests"

    agent do
      schema Zoi.object(%{last_result: Zoi.any() |> Zoi.default(nil), messages: Zoi.list(Zoi.map()) |> Zoi.default([])})

      ai :assistant do
        model(:fast)
        reasoning(:react)

        tools do
          action(ReadTool)
        end

        requests(mode: :session, streaming: true)
        memory(history: :messages)
        result(into: :last_result)
      end
    end

    routes do
      route("ai.react.query", ai: :assistant)
    end
  end

  setup do
    if is_nil(Process.whereis(Jido)) do
      start_supervised!({Jido, name: Jido})
    end

    :ok
  end

  describe "expect_react/1" do
    test "scripts a deterministic ReAct tool loop without stubbing ReqLLM" do
      expect_react do
        user("summarize README")
        call("read", %{path: "README.md"})
        answer("README says Hello.")
      end

      result =
        ReAct.run("summarize README", %{
          model: :fast,
          tools: [ReadTool],
          token_secret: "test-secret-that-is-long-enough-123"
        })

      assert_final_answer(result, "README says Hello.")
      assert_tool_called(result, "read", %{path: "README.md"})
      assert_no_runtime_failure(result)
      assert Enum.any?(result.trace, &(&1.kind == :tool_completed))
    end

    test "returns explicit llm opts for standalone runtime configs" do
      script =
        expect_react do
          user("hello")
          answer("hi")
        end

      result =
        ReAct.run("hello", %{
          model: :fast,
          tools: [],
          llm_opts: react_llm_opts(script),
          token_secret: "test-secret-that-is-long-enough-123"
        })

      assert_final_answer(result, ~r/^hi$/)
      assert_no_runtime_failure(result)
    end

    test "returns request opts for agent requests" do
      script =
        expect_react do
          user("agent hello")
          answer("agent hi")
        end

      suffix = System.unique_integer([:positive, :monotonic])
      registry = Module.concat(__MODULE__, :"AgentRegistry#{suffix}")
      start_supervised!({Registry, keys: :unique, name: registry})

      pid =
        start_supervised!(
          {Jido.AgentServer,
           [
             agent: EchoAgent,
             id: "test-echo-agent-#{suffix}",
             registry: registry
           ]}
        )

      assert {:ok, "agent hi"} = EchoAgent.ask_sync(pid, "agent hello", react_opts(script))
    end

    test "scripts terminal model failures" do
      expect_react do
        user("fail now")
        fail(%{type: :provider_error, message: "boom"})
      end

      result =
        ReAct.run("fail now", %{
          model: :fast,
          tools: [],
          token_secret: "test-secret-that-is-long-enough-123"
        })

      assert result.termination_reason == :failed
      assert %{type: :provider_error, message: "boom"} = result.result
    end

    test "reports malformed explicit scripts as runtime failures" do
      result =
        ReAct.run("bad script", %{
          model: :fast,
          tools: [],
          llm_opts: [jido_ai_react_script: %{user: "", turns: []}],
          token_secret: "test-secret-that-is-long-enough-123"
        })

      assert result.termination_reason == :failed
      assert %{type: :invalid_react_test_script} = result.result
    end

    test "fails explicit scripts that do not match the user prompt" do
      script =
        expect_react do
          user("expected prompt")
          answer("hi")
        end

      result =
        ReAct.run("actual prompt", %{
          model: :fast,
          tools: [],
          llm_opts: react_llm_opts(script),
          token_secret: "test-secret-that-is-long-enough-123"
        })

      assert result.termination_reason == :failed

      assert %{type: :react_test_script_user_mismatch, expected_user: "expected prompt", actual_user: "actual prompt"} =
               result.result
    end

    test "keeps scripted token usage for normal and streaming HTTP requests" do
      for streaming <- [false, true] do
        script =
          expect_react do
            user("usage")
            answer("done", usage: %{input_tokens: 7, output_tokens: 3, total_tokens: 10})
          end

        result =
          ReAct.run("usage", %{
            model: :fast,
            tools: [],
            streaming: streaming,
            llm_opts: react_llm_opts(script)
          })

        assert_final_answer(result, "done")
        assert %{input_tokens: 7, output_tokens: 3, total_tokens: 10} = result.usage
      end
    end

    test "isolates scripts with the same prompt in concurrent callers" do
      parent = self()

      tasks =
        for answer <- ["first", "second"] do
          Task.async(fn ->
            expect_react do
              user("same prompt")
              answer(answer)
            end

            send(parent, {:script_ready, self()})

            receive do
              :run -> :ok
            end

            ReAct.run("same prompt", %{model: :fast, tools: []})
          end)
        end

      for task <- tasks do
        pid = task.pid
        assert_receive {:script_ready, ^pid}
      end

      for task <- tasks, do: send(task.pid, :run)
      assert Enum.map(tasks, &Task.await(&1, 5_000).result) == ["first", "second"]
    end

    test "implicit scripts do not change the checkpoint configuration fingerprint" do
      expect_react do
        user("checkpoint")
        answer("saved")
      end

      config = ReAct.Config.new(%{model: :fast, tools: [], token_secret: "test-checkpoint-secret"})
      result = ReAct.run("checkpoint", config)
      assert_final_answer(result, "saved")
      assert {:ok, state, _payload} = ReAct.Token.decode_state(result.final_token, config)
      assert state.status == :completed
    end

    test "the shared mock closes when its model task ends" do
      parent = self()

      owner =
        Task.async(fn ->
          {:ok, server} = Jido.AI.Test.MockLLM.start_link(script: [], owner: self())
          send(parent, {:owned_mock, server})

          receive do
            :stop -> :ok
          end
        end)

      assert_receive {:owned_mock, server}
      ref = Process.monitor(server)
      send(owner.pid, :stop)
      assert Task.await(owner) == :ok
      assert_receive {:DOWN, ^ref, :process, ^server, :normal}, 1_000
    end

    test "validates scripts before registration" do
      assert_raise ArgumentError, ~r/must end with answer\/1 or fail\/1/, fn ->
        expect_react do
          user("missing terminal")
          call("read", %{path: "README.md"})
        end
      end
    end

    test "rejects duplicate users and nested builders" do
      assert_raise ArgumentError, ~r/only define one/, fn ->
        expect_react do
          user("one")
          user("two")
          answer("done")
        end
      end

      assert :ok = Jido.AI.Test.__start_react_script__()

      assert_raise ArgumentError, ~r/nested expect_react/, fn ->
        Jido.AI.Test.__start_react_script__()
      end

      assert :ok = Jido.AI.Test.__clear_react_script_builder__()
    end

    test "assertion helpers accept trace and string-keyed tool events" do
      events = [
        %{
          kind: :llm_completed,
          data: %{
            "turn_type" => :tool_calls,
            "tool_calls" => [%{"name" => "read", "arguments" => %{"path" => "README.md"}}]
          }
        },
        %{kind: :request_completed, data: %{result: "done"}}
      ]

      assert Jido.AI.Test.assert_final_answer(events, "done") == events
      assert Jido.AI.Test.assert_tool_called(events, :read, %{path: "README.md"}) == events
      assert Jido.AI.Test.assert_tool_called(events, "read") == events
      assert Jido.AI.Test.assert_no_runtime_failure(events) == events
      assert Jido.AI.Test.assert_final_answer(%{trace: events}, ~r/done/) == %{trace: events}
    end

    test "assertion helpers handle malformed sources and calls" do
      assert_raise ExUnit.AssertionError, fn -> Jido.AI.Test.assert_final_answer(:invalid, "done") end

      malformed = [
        %{kind: :llm_completed, data: %{turn_type: :tool_calls, tool_calls: [:bad, %{name: "x"}]}},
        %{kind: :other, data: %{}}
      ]

      assert_raise ExUnit.AssertionError, fn ->
        Jido.AI.Test.assert_tool_called(malformed, "missing", :invalid)
      end

      assert Jido.AI.Test.assert_no_runtime_failure(:invalid) == :invalid
    end

    test "ReActScript public helpers validate malformed scripts and explicit options" do
      assert_raise ArgumentError, fn -> ReActScript.new(%{}) end
      assert_raise ArgumentError, fn -> ReActScript.new(%{user: "hello", turns: []}) end

      assert_raise ArgumentError, ~r/cannot add turns/, fn ->
        ReActScript.new(%{
          user: "hello",
          turns: [%{type: :answer, text: "done"}, %{type: :answer, text: "again"}]
        })
      end

      assert_raise ArgumentError, ~r/invalid react test script turn/, fn ->
        ReActScript.new(%{user: "hello", turns: [%{type: :unknown}]})
      end

      assert_raise ArgumentError, ~r/non-empty tool name/, fn ->
        ReActScript.new(%{
          user: "hello",
          turns: [%{type: :tool_call, name: nil, arguments: %{}}, %{type: :answer, text: "done"}]
        })
      end

      assert_raise ArgumentError, ~r/arguments must be a map/, fn ->
        ReActScript.new(%{
          user: "hello",
          turns: [%{type: :tool_call, name: "read", arguments: []}, %{type: :answer, text: "done"}]
        })
      end

      assert {:error, %{type: :invalid_react_test_script}} =
               ReActScript.next_response([jido_ai_react_script: :bad], [])

      assert :not_scripted = ReActScript.next_response(:bad, :bad)
    end

    test "ReActScript binds registered scripts into maps and nil options" do
      script = ReActScript.new(%{user: "bound", turns: [%{type: :answer, text: "done"}]})
      messages = [%{role: :user, content: "bound"}]

      ReActScript.register(script)
      assert %{jido_ai_react_script: ^script} = ReActScript.bind_messages(messages, %{})
      assert [jido_ai_react_script: ^script] = ReActScript.bind_messages(messages, nil)

      atom_options = %{jido_ai_react_script: :existing}
      string_options = %{"jido_ai_react_script" => :existing}
      assert ReActScript.bind_messages(messages, atom_options) == atom_options
      assert ReActScript.bind_messages(messages, string_options) == string_options
      assert ReActScript.bind_messages(messages, :other) == :other
      assert :ok = ReActScript.clear_current_owner()
    end

    test "ReActScript consumes registered responses and reports exhausted scripts" do
      script = ReActScript.new(%{id: "registered", user: "registered", turns: [%{type: :answer, text: "done"}]})
      ReActScript.register(script)

      assert {:ok, %{message: %{content: "done"}}} =
               ReActScript.next_response([], [%{role: :user, content: "registered"}])

      assert :not_scripted = ReActScript.next_response([], [%{role: :user, content: "registered"}])

      messages = [
        %ReqLLM.Message{role: :user, content: nil},
        %ReqLLM.Message{role: :user, content: "registered"},
        %ReqLLM.Message{role: :assistant, content: nil, tool_calls: []},
        %ReqLLM.Message{role: :assistant, content: nil, tool_calls: [%{id: "call"}]}
      ]

      assert {:error, %{type: :react_test_script_exhausted, script_id: "registered"}} =
               ReActScript.next_response(ReActScript.llm_opts(script), messages)
    end

    test "ReActScript request rejects unsupported request kinds" do
      script = ReActScript.new(%{user: "object", turns: [%{type: :answer, text: "done"}]})

      assert {:error, %{type: :invalid_react_test_script}} =
               ReActScript.request(
                 :object,
                 [%{role: :user, content: "object"}],
                 ReActScript.llm_opts(script),
                 fn _, _ -> flunk("request callback must not run") end
               )
    end
  end
end
