defmodule Jido.AI.Reasoning.ReAct.Actions.HelpersTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.Actions.Helpers

  defmodule ToolA do
    use Jido.Action,
      name: "tool_a",
      description: "Tool A",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, :ok}
  end

  defmodule ToolB do
    use Jido.Action,
      name: "tool_b",
      description: "Tool B",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, :ok}
  end

  describe "build_config/2" do
    test "uses params over context and resolves model alias" do
      params = %{
        model: :capable,
        tools: [ToolA],
        max_iterations: 4,
        llm_timeout_ms: 1_234,
        llm_opts: [thinking: %{type: :enabled, budget_tokens: 512}],
        tool_timeout_ms: 300,
        token_secret: "test-secret"
      }

      context = %{model: :fast, tools: [ToolB], react_token_secret: "context-secret"}
      config = Helpers.build_config(params, context)

      assert config.model == Jido.AI.resolve_model(:capable)
      assert config.max_iterations == 4
      assert config.llm.timeout_ms == 1_234
      assert config.llm.llm_opts == [thinking: %{type: :enabled, budget_tokens: 512}]
      assert config.tool_exec.timeout_ms == 300
      assert config.tools == %{ToolA.name() => ToolA}
      assert config.token.secret == "test-secret"
    end

    test "falls back to context/plugin state tools and default model" do
      params = %{}

      context = %{
        plugin_state: %{
          tool_calling: %{
            tools: %{ToolB.name() => ToolB}
          }
        }
      }

      config = Helpers.build_config(params, context)

      assert config.model == Jido.AI.resolve_model(:fast)
      assert config.tools == %{ToolB.name() => ToolB}
      assert config.max_iterations == 10
    end

    test "respects legacy timeout_ms fallback into llm timeout" do
      config = Helpers.build_config(%{timeout_ms: 999}, %{})
      assert config.llm.timeout_ms == 999
    end

    test "normalizes known string-key llm_opts map entries" do
      config =
        Helpers.build_config(
          %{
            llm_opts: %{
              "thinking" => %{type: :enabled, budget_tokens: 256},
              "reasoning_effort" => :high,
              "unknown_provider_flag" => true
            }
          },
          %{}
        )

      assert Keyword.get(config.llm.llm_opts, :thinking) == %{type: :enabled, budget_tokens: 256}
      assert Keyword.get(config.llm.llm_opts, :reasoning_effort) == :high
      refute Keyword.has_key?(config.llm.llm_opts, :unknown_provider_flag)
    end
  end

  describe "resolve_task_supervisor/2" do
    test "prefers params supervisor when present" do
      params_sup = self()
      context_sup = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(context_sup, :kill) end)

      assert Helpers.resolve_task_supervisor(%{task_supervisor: params_sup}, %{task_supervisor: context_sup}) ==
               params_sup
    end

    test "resolves supervisor from nested context variants" do
      nested_sup = self()
      context = %{agent_state: %{__task_supervisor_skill__: %{supervisor: nested_sup}}}

      assert Helpers.resolve_task_supervisor(%{}, context) == nested_sup
    end
  end

  describe "build_runner_opts/2" do
    test "includes ids, supervisor, and merged runtime context" do
      supervisor = self()

      params = %{
        request_id: "req_1",
        run_id: "run_1",
        task_supervisor: supervisor,
        runtime_context: %{from_params: true}
      }

      context = %{from_context: true}
      opts = Helpers.build_runner_opts(params, context)

      assert opts[:request_id] == "req_1"
      assert opts[:run_id] == "run_1"
      assert opts[:task_supervisor] == supervisor
      assert opts[:context][:from_context] == true
      assert opts[:context][:from_params] == true
    end
  end
end
