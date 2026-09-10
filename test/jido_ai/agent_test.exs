defmodule Jido.AI.AgentTest do
  @moduledoc """
  Tests for Jido.AI.Agent macro and compile-time alias expansion.
  """
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias Jido.AI.Agent
  alias Jido.AI.Session
  alias ReqLLM.Message.ContentPart

  # ============================================================================
  # Test Action Modules (simulating external modules like ash_jido)
  # ============================================================================

  defmodule TestDomain do
    @moduledoc "Mock domain module for testing tool_context resolution"
    def name, do: "test_domain"
  end

  defmodule TestActor do
    @moduledoc "Mock actor module for testing tool_context resolution"
    def name, do: "test_actor"
  end

  defmodule RuntimeAgentSkillProvider do
    def handle(%{operation: :list}, _context, _suffix) do
      {:ok,
       %{resources: [%{id: "briefing://runtime/1", name: "briefing.md", type: :reference, size: 9}], complete: true}}
    end

    def handle(%{operation: :load, resource_id: resource_id}, _context, suffix) do
      content = "Briefing" <> suffix
      {:ok, %{content: content, resource_id: resource_id, size: byte_size(content)}}
    end
  end

  defmodule TestCalculator do
    use Jido.Action,
      name: "calculator",
      description: "A simple calculator"

    def run(%{operation: "add", a: a, b: b}, _ctx), do: {:ok, %{result: a + b}}
    def run(%{operation: "multiply", a: a, b: b}, _ctx), do: {:ok, %{result: a * b}}
  end

  defmodule TestSearch do
    use Jido.Action,
      name: "search",
      description: "Search for information"

    def run(%{query: query}, _ctx), do: {:ok, %{results: ["Found: #{query}"]}}
  end

  defmodule TestSignalAction do
    use Jido.Action,
      name: "signal_action",
      description: "Handles custom agent signals",
      schema: Zoi.object(%{model: Zoi.string()})

    def run(params, context), do: {:ok, Map.merge(context.agent_state, params)}
  end

  defmodule TestRequestTransformer do
    def transform_request(request, _state, _config, _context), do: {:ok, request}
  end

  defmodule ReplacementMemoryPlugin do
    @moduledoc false
    use Jido.Plugin

    def state_spec(options) do
      {:__memory__,
       Zoi.object(%{namespace: Zoi.string() |> Zoi.default(Keyword.get(options, :namespace, "agent:replacement"))})
       |> Zoi.default(%{})}
    end
  end

  # ============================================================================
  # Test Agents Using Agent Macro
  # ============================================================================

  defmodule BasicAgent do
    use Jido.AI.Agent,
      name: "basic_agent",
      description: "A basic test agent",
      tools: [TestCalculator, TestSearch]
  end

  defmodule AgentWithAgentSkills do
    use Jido.AI.Agent,
      name: "agent_with_agent_skills",
      tools: [TestCalculator],
      system_prompt: "Base instructions.",
      agent_skills: ["priv/skills"]
  end

  defmodule AgentWithRuntimeAgentSkills do
    use Jido.AI.Agent,
      name: "agent_with_runtime_agent_skills",
      tools: [TestCalculator],
      system_prompt: "Base instructions.",
      agent_skills: [
        specs: [
          %Jido.AI.Skill.Spec{
            name: "runtime-briefing",
            description: "Load runtime briefing resources.",
            body_ref: {:inline, "Runtime briefing instructions."},
            metadata: %{"owner" => "test"},
            allowed_tools: ["calculator"],
            tags: ["runtime"]
          }
        ],
        resource_provider: {RuntimeAgentSkillProvider, :handle, ["!"]}
      ]
  end

  defmodule AgentWithToolContext do
    use Jido.AI.Agent,
      name: "agent_with_context",
      tools: [TestCalculator],
      tool_context: %{
        domain: TestDomain,
        actor: TestActor,
        static_value: "hello"
      }
  end

  defmodule AgentWithPlainMapContext do
    use Jido.AI.Agent,
      name: "agent_with_plain_map",
      tools: [TestCalculator],
      tool_context: %{tenant_id: "tenant_123", enabled: true}
  end

  defmodule AgentWithLlmOpts do
    use Jido.AI.Agent,
      name: "agent_with_llm_opts",
      tools: [TestCalculator],
      llm_opts: [thinking: %{type: :enabled, budget_tokens: 800}, reasoning_effort: :high],
      req_http_options: [adapter: [recv_timeout: 2_000]]
  end

  defmodule AgentWithStreamingDisabled do
    use Jido.AI.Agent,
      name: "agent_no_streaming",
      tools: [TestCalculator],
      streaming: false
  end

  defmodule AgentWithMaxTokens do
    use Jido.AI.Agent,
      name: "agent_with_max_tokens",
      tools: [TestCalculator],
      max_tokens: 4_096
  end

  defmodule AgentWithStreamTimeout do
    use Jido.AI.Agent,
      name: "agent_with_stream_timeout",
      tools: [TestCalculator],
      stream_timeout_ms: 123_456
  end

  defmodule AgentWithRequestTransformer do
    use Jido.AI.Agent,
      name: "agent_with_request_transformer",
      tools: [TestCalculator],
      request_transformer: TestRequestTransformer
  end

  defmodule AgentWithInlineModelMap do
    use Jido.AI.Agent,
      name: "agent_with_inline_model_map",
      tools: [TestCalculator],
      model: %{provider: :openai, id: "gpt-4o-mini", base_url: "http://localhost:4000/v1"}
  end

  defmodule AgentWithTupleModelSpec do
    use Jido.AI.Agent,
      name: "agent_with_tuple_model_spec",
      tools: [TestCalculator],
      model: {:openai, "gpt-4o-mini", []}
  end

  defmodule AgentWithStreamTimeoutAlias do
    use Jido.AI.Agent,
      name: "agent_with_stream_timeout_alias",
      tools: [TestCalculator],
      stream_timeout_ms: 45_000
  end

  defmodule AgentWithModuleAttrSystemPrompt do
    @my_prompt "You are a helpful testing assistant."

    use Jido.AI.Agent,
      name: "agent_with_attr_prompt",
      tools: [TestCalculator],
      system_prompt: @my_prompt
  end

  defmodule AgentWithFalseSystemPrompt do
    use Jido.AI.Agent,
      name: "agent_with_false_prompt",
      tools: [TestCalculator],
      system_prompt: false
  end

  defmodule AgentWithNilSystemPrompt do
    use Jido.AI.Agent,
      name: "agent_with_nil_prompt",
      tools: [TestCalculator],
      system_prompt: nil
  end

  defmodule AgentWithSignalRoutes do
    use Jido.AI.Agent,
      name: "agent_with_signal_routes",
      tools: [TestCalculator],
      signal_routes: [
        {"custom.state.patch", TestSignalAction}
      ]
  end

  defmodule AgentWithSignalRouteStaticParams do
    use Jido.AI.Agent,
      name: "agent_with_signal_route_static_params",
      tools: [TestCalculator],
      signal_routes: [
        {"custom.static", {TestSignalAction, %{mode: :patch}}}
      ]
  end

  defmodule AgentWithSignalRoutesFromAttribute do
    @signal_routes [{"custom.attr.patch", TestSignalAction}]

    use Jido.AI.Agent,
      name: "agent_with_signal_routes_from_attribute",
      tools: [TestCalculator],
      signal_routes: @signal_routes
  end

  defmodule AgentWithoutDefaultMemory do
    use Jido.AI.Agent,
      name: "agent_without_default_memory",
      tools: [TestCalculator],
      default_plugins: false
  end

  defmodule AgentWithReplacementMemory do
    use Jido.AI.Agent,
      name: "agent_with_replacement_memory",
      tools: [TestCalculator],
      plugins: [{ReplacementMemoryPlugin, namespace: "agent:ai-replacement"}]
  end

  # ============================================================================
  # expand_aliases_in_ast/2 Tests
  # ============================================================================

  describe "expand_aliases_in_ast/2" do
    test "expands module aliases to atoms" do
      # Simulate AST for %{domain: TestDomain}
      ast = {:%{}, [], [domain: {:__aliases__, [alias: false], [:SomeModule]}]}

      # Create a mock caller env
      env = __ENV__

      # The function should walk the AST and expand aliases
      result = Agent.expand_aliases_in_ast(ast, env)

      # The __aliases__ node should be expanded (in this case to SomeModule atom)
      assert is_tuple(result)
    end

    test "allows literal values unchanged" do
      ast = {:%{}, [], [key: "string", num: 42, flag: true, atom_val: :test]}
      env = __ENV__

      result = Agent.expand_aliases_in_ast(ast, env)

      # Should preserve the structure
      assert is_tuple(result)
    end

    test "allows nested maps" do
      ast = {:%{}, [], [outer: {:%{}, [], [inner: "value"]}]}
      env = __ENV__

      result = Agent.expand_aliases_in_ast(ast, env)

      assert is_tuple(result)
    end

    test "allows lists" do
      ast = {:%{}, [], [items: [1, 2, 3]]}
      env = __ENV__

      result = Agent.expand_aliases_in_ast(ast, env)

      assert is_tuple(result)
    end

    test "raises CompileError for function calls" do
      # Simulate AST for %{value: some_function()}
      ast = {:%{}, [], [value: {:some_function, [line: 1], []}]}
      env = __ENV__

      assert_raise CompileError, ~r/Unsafe construct.*function call/, fn ->
        Agent.expand_aliases_in_ast(ast, env)
      end
    end
  end

  # ============================================================================
  # Agent Macro Compilation Tests
  # ============================================================================

  describe "Agent macro" do
    test "compiles agent with basic options" do
      assert function_exported?(BasicAgent, :ask, 2)
      assert function_exported?(BasicAgent, :ask, 3)
      assert function_exported?(BasicAgent, :ask_stream, 3)
      assert function_exported?(BasicAgent, :steer, 3)
      assert function_exported?(BasicAgent, :inject, 3)
      assert function_exported?(BasicAgent, :definition, 0)
      assert function_exported?(BasicAgent, :new, 0)
    end

    test "agent has correct name" do
      agent = BasicAgent.new!()
      assert agent.name == "basic_agent"
    end

    test "agent has correct description" do
      agent = BasicAgent.new!()
      assert agent.description == "A basic test agent"
    end

    test "uses declared AI plugins when core defaults are disabled" do
      modules = Enum.map(AgentWithoutDefaultMemory.definition().plugins, &elem(&1, 0))

      assert Jido.AI.Session.Plugin in modules
      assert modules == Enum.uniq(modules)
    end

    test "adds an explicit configured plugin" do
      modules = Enum.map(AgentWithReplacementMemory.definition().plugins, &elem(&1, 0))
      agent = AgentWithReplacementMemory.new!()

      assert ReplacementMemoryPlugin in modules
      assert agent.state[:__memory__].namespace == "agent:ai-replacement"
    end

    test "tool_context with module aliases resolves correctly" do
      agent = AgentWithToolContext.new!()
      config = Jido.AI.get_strategy_config(agent)

      # Modules should be resolved to atoms, not AST tuples
      # Now stored as base_tool_context (persistent)
      assert config.base_tool_context[:domain] == TestDomain
      assert config.base_tool_context[:actor] == TestActor
      assert config.base_tool_context[:static_value] == "hello"
    end

    test "tool_context with plain map values works" do
      agent = AgentWithPlainMapContext.new!()
      config = Jido.AI.get_strategy_config(agent)

      # Now stored as base_tool_context (persistent)
      assert config.base_tool_context[:tenant_id] == "tenant_123"
      assert config.base_tool_context[:enabled] == true
    end

    test "llm_opts and req_http_options are forwarded into strategy config" do
      agent = AgentWithLlmOpts.new!()
      config = Jido.AI.get_strategy_config(agent)

      assert config.thinking == %{type: :enabled, budget_tokens: 800}
      assert config.reasoning_effort == :high
      assert config.req_http_options == [adapter: [recv_timeout: 2_000]]
    end

    test "streaming: false is forwarded into strategy config" do
      agent = AgentWithStreamingDisabled.new!()
      config = Jido.AI.get_strategy_config(agent)

      assert config.streaming == false
    end

    test "max_tokens is forwarded into strategy config" do
      agent = AgentWithMaxTokens.new!()
      config = Jido.AI.get_strategy_config(agent)

      assert config.max_tokens == 4_096
    end

    test "stream_timeout_ms is forwarded into strategy config" do
      agent = AgentWithStreamTimeout.new!()
      {:ok, profile} = Jido.AI.Configuration.profile(agent)
      assert profile.requests.idle_timeout == 123_456
    end

    test "request_transformer is forwarded into strategy config" do
      agent = AgentWithRequestTransformer.new!()
      {:ok, profile} = Jido.AI.Configuration.profile(agent)
      assert profile.reasoning.request_transformer == TestRequestTransformer
    end

    test "inline map model specs are evaluated and forwarded into strategy config" do
      agent = AgentWithInlineModelMap.new!()
      config = Jido.AI.get_strategy_config(agent)

      assert config.model == %{provider: :openai, id: "gpt-4o-mini", base_url: "http://localhost:4000/v1"}
    end

    test "tuple model specs are evaluated and forwarded into strategy config" do
      agent = AgentWithTupleModelSpec.new!()
      config = Jido.AI.get_strategy_config(agent)

      assert config.model == {:openai, "gpt-4o-mini", []}
    end

    test "stream_timeout_ms alias is forwarded into strategy config" do
      agent = AgentWithStreamTimeoutAlias.new!()
      {:ok, profile} = Jido.AI.Configuration.profile(agent)
      assert profile.requests.idle_timeout == 45_000
    end

    test "system_prompt from module attribute is resolved at compile time" do
      agent = AgentWithModuleAttrSystemPrompt.new!()
      config = Jido.AI.get_strategy_config(agent)

      assert config.system_prompt == "You are a helpful testing assistant."
    end

    test "false system_prompt is treated as omitted" do
      default_config = Jido.AI.get_strategy_config(BasicAgent.new!())
      config = Jido.AI.get_strategy_config(AgentWithFalseSystemPrompt.new!())

      assert config.system_prompt == default_config.system_prompt
    end

    test "nil system_prompt is treated as omitted" do
      default_config = Jido.AI.get_strategy_config(BasicAgent.new!())
      config = Jido.AI.get_strategy_config(AgentWithNilSystemPrompt.new!())

      assert config.system_prompt == default_config.system_prompt
    end

    test "signal_routes option is forwarded to the base agent" do
      expected_routes = [{"custom.state.patch", TestSignalAction}]

      routes = AgentWithSignalRoutes.definition().routes

      assert Enum.all?(expected_routes, fn {path, target} ->
               Enum.any?(routes, &(&1.path == path and &1.target == target))
             end)
    end

    test "signal_routes option supports static params route format" do
      assert Enum.any?(
               AgentWithSignalRouteStaticParams.definition().routes,
               &(&1.path == "custom.static" and &1.target == {TestSignalAction, %{mode: :patch}})
             )
    end

    test "signal_routes option supports module attributes" do
      assert Enum.any?(
               AgentWithSignalRoutesFromAttribute.definition().routes,
               &(&1.path == "custom.attr.patch" and &1.target == TestSignalAction)
             )
    end

    test "signal_routes option is used by AgentServer routing" do
      suffix = System.unique_integer([:positive, :monotonic])
      registry = Module.concat(__MODULE__, :"SignalRouteRegistry#{suffix}")
      start_supervised!({Registry, keys: :unique, name: registry})

      pid =
        start_supervised!(
          {Jido.AgentServer,
           [
             agent: AgentWithSignalRoutes,
             id: "signal-route-agent-#{suffix}",
             registry: registry
           ]}
        )

      signal =
        Jido.Signal.new!("custom.state.patch", %{model: "signal-model"}, source: "/jido_ai/agent_test")

      assert {:ok, agent} = Jido.AgentServer.call(pid, signal)
      assert agent.state.model == "signal-model"

      assert Jido.AgentServer.agent(pid).state.model == "signal-model"
    end

    test "raises when module attribute system_prompt does not resolve to a binary" do
      module_name = Module.concat(__MODULE__, :"InvalidPromptAgent#{System.unique_integer([:positive, :monotonic])}")

      source = """
      defmodule #{inspect(module_name)} do
        @prompt 123

        use Jido.AI.Agent,
          name: "invalid_prompt_agent",
          tools: [#{inspect(TestCalculator)}],
          system_prompt: @prompt
      end
      """

      assert_raise CompileError, ~r/system_prompt must be a binary, nil, false/, fn ->
        Code.compile_string(source)
      end
    end

    test "tools list resolves module aliases" do
      agent = BasicAgent.new!()
      tools = Jido.AI.list_tools(agent)

      # Should be actual module atoms, not AST
      assert TestCalculator in tools
      assert TestSearch in tools
      assert Enum.all?(tools, &is_atom/1)
    end

    test "agent_skills wires the catalog, loading tool, and scoped specs" do
      agent = AgentWithAgentSkills.new!()
      profile = Agent.profile(agent, :assistant)

      assert profile.instructions == "Base instructions."
      assert profile.skills.paths == ["priv/skills"]
      assert Jido.AI.list_tools(agent) == [TestCalculator]

      server = start_agent(agent)

      assert {:ok, %{specs: specs, index: index, diagnostics: diagnostics}} =
               Session.skill_catalog(server)

      assert Enum.map(specs, & &1.name) == ["code-review", "unit-converter"]
      assert index =~ "**code-review**"
      assert index =~ "**unit-converter**"
      refute index =~ "# Code Review"
      assert %Jido.AI.Skill.Diagnostics{} = diagnostics
    end

    test "agent_skills accepts runtime specs and an MFA resource provider" do
      agent = AgentWithRuntimeAgentSkills.new!()
      profile = Agent.profile(agent, :assistant)

      assert profile.instructions == "Base instructions."
      assert [spec] = profile.skills.specs
      assert spec.name == "runtime-briefing"
      assert spec.body_ref == {:inline, "Runtime briefing instructions."}

      assert profile.skills.resource_provider ==
               {RuntimeAgentSkillProvider, :handle, ["!"]}

      server = start_agent(agent)

      assert {:ok, %{specs: [loaded], index: index}} = Session.skill_catalog(server)
      assert loaded == spec
      assert index =~ "**runtime-briefing**"
      refute index =~ "Runtime briefing instructions."
    end

    @tag :tmp_dir
    test "agent_skills resolves at agent initialization instead of module compilation", %{tmp_dir: tmp_dir} do
      skill_dir = Path.join(tmp_dir, "runtime-skill")
      File.mkdir_p!(skill_dir)
      skill_file = Path.join(skill_dir, "SKILL.md")

      File.write!(skill_file, "---\nname: runtime-skill\ndescription: Compile-time version\n---\n\nOld body\n")

      module_name = Module.concat(__MODULE__, :"RuntimeSkillsAgent#{System.unique_integer([:positive, :monotonic])}")

      Code.compile_string("""
      defmodule #{inspect(module_name)} do
        use Jido.AI.Agent,
          name: "runtime_skills_agent",
          tools: [#{inspect(TestCalculator)}],
          agent_skills: [#{inspect(tmp_dir)}]
      end
      """)

      File.write!(skill_file, "---\nname: runtime-skill\ndescription: Runtime version\n---\n\nNew body\n")

      agent = module_name.new!()
      profile = Agent.profile(agent, :assistant)
      assert profile.instructions =~ "helpful AI assistant"
      refute profile.instructions =~ "Runtime version"

      server = start_agent(agent)
      assert {:ok, %{specs: [spec], index: index}} = Session.skill_catalog(server)

      assert index =~ "Runtime version"
      refute index =~ "Compile-time version"
      assert spec.body_ref == {:file, skill_file}
      refute inspect(spec) =~ "New body"
    end

    test "does not warn when consumer defines its own thinking_meta/1" do
      module_name = Module.concat(__MODULE__, :"CollisionAgent#{System.unique_integer([:positive, :monotonic])}")

      source = """
      defmodule #{inspect(module_name)} do
        use Jido.AI.Agent,
          name: "collision_agent",
          tools: [#{inspect(TestCalculator)}]

        defp thinking_meta(_), do: %{custom: true}
      end
      """

      warnings =
        capture_io(:stderr, fn ->
          Code.compile_string(source)
        end)

      refute warnings =~ "this clause for thinking_meta/1 cannot match"
    end
  end

  # ============================================================================
  # ask/3 with Per-Request Tool Context
  # ============================================================================

  describe "ask/3 with tool_context option" do
    test "ask/2 works without options" do
      # We can't fully test without starting a server, but we can verify the function exists
      assert function_exported?(BasicAgent, :ask, 2)
      assert function_exported?(BasicAgent, :ask, 3)
    end

    test "ask/3 accepts tool_context option" do
      # The function signature should accept opts
      # This is a compile-time check - the function is generated by the macro
      assert :erlang.fun_info(&BasicAgent.ask/3, :arity) == {:arity, 3}
    end

    test "ask_stream/3 exists as stream wrapper" do
      assert :erlang.fun_info(&BasicAgent.ask_stream/3, :arity) == {:arity, 3}
    end

    test "generated request helpers surface unsupported file reference options before dispatch" do
      unless function_exported?(ContentPart, :file_id, 3) do
        assert {:error, {:unsupported_content_part_file_id, _message}} =
                 BasicAgent.ask(self(), "Summarize this.", file_id: "file_123")

        assert {:error, {:unsupported_content_part_file_id, _message}} =
                 BasicAgent.ask_stream(self(), "Summarize this.", file_id: "file_123")

        assert {:error, {:unsupported_content_part_file_id, _message}} =
                 BasicAgent.ask_sync(self(), "Summarize this.", file_id: "file_123", timeout: 1)
      end
    end
  end

  # ============================================================================
  # tools_from_skills/1 Tests
  # ============================================================================

  describe "tools_from_skills/1" do
    defmodule MockSkill do
      def actions, do: [TestCalculator, TestSearch]
    end

    defmodule MockSkill2 do
      def actions, do: [TestSearch]
    end

    test "extracts actions from skill modules" do
      tools = Agent.tools_from_skills([MockSkill])

      assert TestCalculator in tools
      assert TestSearch in tools
    end

    test "deduplicates actions from multiple skills" do
      tools = Agent.tools_from_skills([MockSkill, MockSkill2])

      # Should have unique entries only
      assert length(Enum.filter(tools, &(&1 == TestSearch))) == 1
    end

    test "returns empty list for empty input" do
      assert Agent.tools_from_skills([]) == []
    end
  end

  defp start_agent(agent) do
    jido = :"agent_test_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    assert {:ok, server} = Jido.start_agent(jido, agent)
    server
  end
end
