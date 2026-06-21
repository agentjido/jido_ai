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
      tools: [ReadTool],
      token_secret: "test-secret-that-is-long-enough-123"
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

      {:ok, pid} =
        Jido.AgentServer.start_link(
          agent: EchoAgent,
          id: "test-echo-agent-#{suffix}",
          registry: registry
        )

      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

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
