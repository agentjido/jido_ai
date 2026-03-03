defmodule Jido.AI.CoreTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI
  alias Jido.Agent.Strategy.State, as: StratState

  defmodule ValidTool do
    use Jido.Action,
      name: "valid_tool",
      description: "Valid tool",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, :ok}
  end

  defmodule IncompleteTool do
    def name, do: "incomplete_tool"
  end

  setup :set_mimic_from_context

  setup do
    old_aliases = Application.get_env(:jido_ai, :model_aliases)
    old_defaults = Application.get_env(:jido_ai, :llm_defaults)

    on_exit(fn ->
      if is_nil(old_aliases) do
        Application.delete_env(:jido_ai, :model_aliases)
      else
        Application.put_env(:jido_ai, :model_aliases, old_aliases)
      end

      if is_nil(old_defaults) do
        Application.delete_env(:jido_ai, :llm_defaults)
      else
        Application.put_env(:jido_ai, :llm_defaults, old_defaults)
      end
    end)

    :ok
  end

  describe "model aliases and llm defaults" do
    test "model_aliases/0 merges configured aliases over defaults" do
      Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4.1-mini", custom: "test:custom"})
      aliases = AI.model_aliases()

      assert aliases[:fast] == "openai:gpt-4.1-mini"
      assert aliases[:custom] == "test:custom"
      assert is_binary(aliases[:capable])
    end

    test "resolve_model/1 passes strings, resolves aliases, and raises for unknown alias" do
      assert AI.resolve_model("openai:gpt-4.1") == "openai:gpt-4.1"
      assert is_binary(AI.resolve_model(:fast))

      assert_raise ArgumentError, ~r/Unknown model alias/, fn ->
        AI.resolve_model(:does_not_exist)
      end
    end

    test "llm_defaults merges configured maps and validates kind" do
      Application.put_env(:jido_ai, :llm_defaults, %{text: %{max_tokens: 55, temperature: 0.6}})

      defaults = AI.llm_defaults()
      assert defaults[:text][:max_tokens] == 55
      assert defaults[:text][:temperature] == 0.6

      text_defaults = AI.llm_defaults(:text)
      assert text_defaults[:max_tokens] == 55

      assert_raise ArgumentError, ~r/Unknown LLM defaults kind/, fn ->
        AI.llm_defaults(:unknown)
      end
    end
  end

  describe "llm facade wrappers" do
    test "generate_text/2 resolves model and merges req options" do
      Mimic.stub(ReqLLM.Generation, :generate_text, fn model, messages, opts ->
        assert model == AI.resolve_model(:fast)
        assert Enum.map(messages, & &1.role) == [:system, :user]
        assert hd(Enum.at(messages, 0).content).text == "System"
        assert hd(Enum.at(messages, 1).content).text == "hello"
        assert opts[:max_tokens] == 99
        assert opts[:temperature] == 0.9
        assert opts[:receive_timeout] == 777
        assert opts[:tool_choice] == :none
        assert opts[:foo] == :bar
        {:ok, %{message: %{content: "ok"}}}
      end)

      assert {:ok, %{message: %{content: "ok"}}} =
               AI.generate_text("hello",
                 model: :fast,
                 system_prompt: "System",
                 max_tokens: 99,
                 temperature: 0.9,
                 timeout: 777,
                 tool_choice: :none,
                 opts: [foo: :bar]
               )
    end

    test "generate_object/3 uses object defaults and passes schema/options through" do
      schema = %{type: "object", properties: %{"name" => %{type: "string"}}}

      Mimic.stub(ReqLLM.Generation, :generate_object, fn model, messages, object_schema, opts ->
        assert model == AI.resolve_model(:thinking)
        assert Enum.map(messages, & &1.role) == [:user]
        assert hd(Enum.at(messages, 0).content).text == "extract"
        assert object_schema == schema
        assert opts[:max_tokens] == 222
        assert opts[:receive_timeout] == 888
        {:ok, %{object: %{"name" => "Alice"}}}
      end)

      assert {:ok, %{object: %{"name" => "Alice"}}} =
               AI.generate_object("extract", schema, max_tokens: 222, timeout: 888)
    end

    test "stream_text/2 delegates to ReqLLM.stream_text/3" do
      Mimic.stub(ReqLLM, :stream_text, fn model, messages, opts ->
        assert model == AI.resolve_model(:fast)
        assert Enum.map(messages, & &1.role) == [:user]
        assert hd(Enum.at(messages, 0).content).text == "stream this"
        assert opts[:max_tokens] == 10
        {:ok, %{stream: []}}
      end)

      assert {:ok, %{stream: []}} = AI.stream_text("stream this", max_tokens: 10)
    end

    test "ask/2 extracts normalized text from generate_text response" do
      Mimic.stub(ReqLLM.Generation, :generate_text, fn _model, _messages, _opts ->
        {:ok, %{message: %{content: "final answer"}}}
      end)

      assert {:ok, "final answer"} = AI.ask("What is the answer?")
    end
  end

  describe "tool management wrappers" do
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
      agent = %Jido.Agent{state: %{StratState.key() => %{config: %{tools: [ValidTool]}}}}

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
