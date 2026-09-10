defmodule Jido.AI.CoreTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI
  alias Jido.Agent.Strategy.State, as: StratState

  defmodule ValidTool do
    use Jido.Action,
      name: "valid_tool",
      description: "Valid tool",
      schema: Zoi.object(%{})

    @impl true
    def run(_params, _context), do: {:ok, :ok}
  end

  defmodule IncompleteTool do
    def name, do: "incomplete_tool"
  end

  setup :set_mimic_from_context

  setup do
    old_aliases = Application.get_env(:jido_ai, :model_aliases)

    on_exit(fn ->
      if is_nil(old_aliases) do
        Application.delete_env(:jido_ai, :model_aliases)
      else
        Application.put_env(:jido_ai, :model_aliases, old_aliases)
      end
    end)

    :ok
  end

  defp with_model_aliases(aliases, fun) do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, aliases)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido_ai, :model_aliases)
      else
        Application.put_env(:jido_ai, :model_aliases, original)
      end
    end)

    fun.()
  end

  describe "model aliases" do
    test "model_aliases/0 merges application aliases over package configuration" do
      aliases =
        with_model_aliases(%{fast: "openai:gpt-4.1-mini", custom: "test:custom"}, fn ->
          AI.model_aliases()
        end)

      assert aliases[:fast] == "openai:gpt-4.1-mini"
      assert aliases[:custom] == "test:custom"
      assert is_binary(aliases[:capable])
    end

    test "model_aliases/0 supports direct model specs for configured aliases" do
      inline_model = %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}

      aliases = with_model_aliases(%{capable: inline_model}, fn -> AI.model_aliases() end)
      assert aliases[:capable] == inline_model
    end

    test "resolve_model/1 passes strings, resolves aliases, and raises for unknown alias" do
      assert AI.resolve_model("openai:gpt-4.1") == "openai:gpt-4.1"
      assert is_binary(AI.resolve_model(:fast))

      assert_raise ArgumentError, ~r/Unknown model alias/, fn ->
        AI.resolve_model(:does_not_exist)
      end
    end

    test "resolve_model/1 resolves aliases to direct model specs" do
      inline_model = %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}

      with_model_aliases(%{capable: inline_model}, fn ->
        assert AI.resolve_model(:capable) == inline_model
      end)
    end

    test "resolve_model/1 accepts ReqLLM tuple, inline map, and model struct inputs" do
      tuple_model = {:openai, "gpt-4.1", [reasoning_effort: :medium]}
      inline_model = %{provider: :openai, id: "gpt-4.1", base_url: "http://localhost:4000/v1"}
      struct_model = LLMDB.Model.new!(%{provider: :openai, id: "gpt-4.1"})

      assert AI.resolve_model(tuple_model) == tuple_model
      assert AI.resolve_model(inline_model) == inline_model
      assert AI.resolve_model(struct_model) == struct_model
    end

    test "resolve_model/1 raises for invalid configured alias specs" do
      with_model_aliases(%{capable: [:invalid]}, fn ->
        assert_raise ArgumentError, ~r/Invalid model configured for alias :capable/, fn ->
          AI.resolve_model(:capable)
        end
      end)
    end

    test "resolve_model/1 raises for unsupported direct model inputs" do
      assert_raise ArgumentError, ~r/Expected a valid ReqLLM model input/, fn ->
        AI.resolve_model(123)
      end
    end
  end

  describe "tool management wrappers" do
    @describetag :legacy_v2

    test "register_tool validates module presence and callbacks" do
      assert {:error, {:not_loaded, Missing.Tool}} = AI.register_tool(self(), Missing.Tool)
      assert {:error, :not_a_tool} = AI.register_tool(self(), IncompleteTool)
    end

    test "register_tool delegates through AgentServer call" do
      Mimic.stub(Jido.AgentServer, :call, fn _server, signal, timeout ->
        assert signal.type == "ai.react.register_tool"
        assert signal.data.tool_module == ValidTool
        assert timeout == 5_000
        {:ok, :registered}
      end)

      assert {:ok, :registered} = AI.register_tool(self(), ValidTool)
    end

    test "register_tool_direct validates and updates strategy tool config without AgentServer call" do
      agent = %Jido.Agent{module: Jido.Agent, name: "fixture", schema: Zoi.object(%{}), state: %{}}

      assert {:error, {:not_loaded, Missing.Tool}} =
               AI.register_tool_direct(agent, Missing.Tool)

      assert {:error, :not_a_tool} = AI.register_tool_direct(agent, IncompleteTool)

      assert {:ok, agent} = AI.register_tool_direct(agent, ValidTool)

      config = AI.get_strategy_config(agent)
      assert config.tools == [ValidTool]
      assert config.actions_by_name == %{"valid_tool" => ValidTool}
      assert AI.list_tools(agent) == [ValidTool]
      assert AI.has_tool?(agent, "valid_tool")
    end

    test "unregister_tool_direct removes tool config without AgentServer call" do
      agent = %Jido.Agent{module: Jido.Agent, name: "fixture", schema: Zoi.object(%{}), state: %{}}
      assert {:ok, agent} = AI.register_tool_direct(agent, ValidTool)
      assert {:ok, agent} = AI.unregister_tool_direct(agent, "valid_tool")

      config = AI.get_strategy_config(agent)
      assert config.tools == []
      assert config.actions_by_name == %{}
      assert config.reqllm_tools == []
      assert AI.list_tools(agent) == []
      refute AI.has_tool?(agent, "valid_tool")
    end

    test "unregister_tool and set_system_prompt wrap signals and delegate call" do
      Mimic.stub(Jido.AgentServer, :call, fn _server, signal, timeout ->
        assert timeout == 5_000

        case signal.type do
          "ai.react.unregister_tool" ->
            assert signal.data.tool_name == "valid_tool"
            {:ok, :unregistered}

          "ai.react.set_system_prompt" ->
            assert signal.data.system_prompt == "Be concise"
            {:ok, :prompt_set}
        end
      end)

      assert {:ok, :unregistered} = AI.unregister_tool(self(), "valid_tool")
      assert {:ok, :prompt_set} = AI.set_system_prompt(self(), "Be concise")
    end

    test "list_tools and has_tool work for agent struct and server wrappers" do
      agent = %Jido.Agent{
        module: Jido.Agent,
        name: "fixture",
        schema: Zoi.object(%{}),
        state: %{StratState.key() => %{config: %{tools: [ValidTool]}}}
      }

      assert AI.list_tools(agent) == [ValidTool]
      assert AI.has_tool?(agent, "valid_tool")

      Mimic.stub(Jido.AgentServer, :state, fn _server -> {:ok, %{agent: agent}} end)

      assert {:ok, [ValidTool]} = AI.list_tools(self())
      assert {:ok, true} = AI.has_tool?(self(), "valid_tool")
      assert {:ok, false} = AI.has_tool?(self(), "missing_tool")
    end

    test "list_tools and has_tool return passthrough errors for server state failures" do
      Mimic.stub(Jido.AgentServer, :state, fn _server -> {:error, :not_found} end)

      assert {:error, :not_found} = AI.list_tools(self())
      assert {:error, :not_found} = AI.has_tool?(self(), "valid_tool")
    end
  end
end
