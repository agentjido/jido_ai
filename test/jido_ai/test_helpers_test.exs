defmodule Jido.AI.TestHelpersTest do
  use Jido.AI.TestCase, async: false

  alias Jido.AI.Reasoning.ReAct

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
    use Jido.AI.Agent,
      name: "test_echo_agent",
      description: "Agent used by public test helper tests",
      tools: [ReadTool]
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
  end
end
