defmodule Jido.AI.Agent do
  @moduledoc """
  Defines a graph-first AI Agent.

  `use Jido.AI.Agent` builds a normal `Jido.Agent`. The required `ai` block
  selects one root reasoning Flow:

      defmodule MyApp.SupportAgent do
        use Jido.AI.Agent,
          id: "my_app/agents/support",
          name: "support_agent"

        ai do
          reasoning MyApp.SupportReasoning
        end
      end

  The reasoning Flow is the direct executable target of the Agent request
  route. Jido AI does not insert a hidden pipeline around it.

  Small Agents can define the root Flow inline:

      ai do
        reasoning do
          step "answer", question <- input(:question) do
            {:ok, %{answer: question}}
          end

          output result("answer")
        end
      end

  The generated Agent accepts `jido.ai.request` Signals and replies with a
  `jido.ai.response` Signal. The route does not change Agent state.

  The `ai` block lowers to the normal Jido Agent route model at compile time.
  `Jido.AI.Agent.Codec` gives this authoring boundary a versioned
  `jido.ai.agent` document. It stores the core Agent fields and a trusted
  reference to the root reasoning Flow.
  """

  @request_type "jido.ai.request"
  @response_type "jido.ai.response"

  @doc "Uses the Jido Agent runtime with the graph-first AI authoring layer."
  defmacro __using__(options) do
    options = Jido.Agent.options!(options, __CALLER__)
    signal_source = "/" <> options[:id]
    Module.put_attribute(__CALLER__.module, :jido_ai_signal_source, signal_source)

    quote do
      use Jido.Agent, unquote(Macro.escape(options))

      import Jido.AI.Agent, only: [ai: 1]

      @before_compile Jido.AI.Agent
    end
  end

  @doc false
  defmacro __before_compile__(caller) do
    unless Module.get_attribute(caller.module, :jido_ai_block_declared) do
      compile_error!(caller, caller.line, "Jido.AI.Agent requires one ai block")
    end

    quote do
    end
  end

  @doc "Defines the one root reasoning Flow for an AI Agent."
  defmacro ai(do: block) do
    caller = __CALLER__
    ensure_single_ai_block!(caller)

    case reasoning_declaration!(block, caller) do
      {:module, target, line} -> module_reasoning(target, line, caller)
      {:inline, body, line} -> inline_reasoning(body, line, caller)
    end
  end

  defp ensure_single_ai_block!(caller) do
    if Module.get_attribute(caller.module, :jido_ai_block_declared) do
      compile_error!(caller, caller.line, "An Agent can define only one ai block")
    end

    Module.put_attribute(caller.module, :jido_ai_block_declared, true)
  end

  defp reasoning_declaration!(block, caller) do
    case expressions(block) do
      [{:reasoning, metadata, [[do: body]]}] ->
        {:inline, body, metadata[:line]}

      [{:reasoning, metadata, [target]}] ->
        {:module, reasoning_module!(target, metadata[:line], caller), metadata[:line]}

      [{:reasoning, metadata, arguments}] when is_list(arguments) ->
        compile_error!(
          caller,
          metadata[:line],
          "reasoning requires one Flow module or one do block"
        )

      declarations ->
        lines = Enum.map(declarations, &expression_line(&1, caller.line))
        line = List.first(lines) || caller.line

        compile_error!(
          caller,
          line,
          "ai requires exactly one reasoning declaration"
        )
    end
  end

  defp reasoning_module!(target_ast, line, caller) do
    target = Macro.expand(target_ast, caller)

    with true <- is_atom(target) and target not in [nil, true, false],
         {:module, ^target} <- Code.ensure_compiled(target),
         {:ok, %{kind: :flow}} <- Jido.Instruction.resolve(target) do
      target
    else
      _reason ->
        compile_error!(caller, line, "reasoning must reference a compiled Jido Flow module")
    end
  end

  defp module_reasoning(target, line, caller) do
    signal_source = signal_source!(caller)

    quote line: line do
      routes do
        signal_source unquote(signal_source)

        route unquote(@request_type), unquote(target), as: :request do
          state(:unchanged)
          reply(unquote(@response_type), from: output())
        end
      end
    end
  end

  defp inline_reasoning(body, line, caller) do
    signal_source = signal_source!(caller)

    quote line: line do
      routes do
        signal_source unquote(signal_source)

        route unquote(@request_type), as: :request do
          flow name: "reasoning" do
            unquote(body)
          end

          state(:unchanged)
          reply(unquote(@response_type), from: output())
        end
      end
    end
  end

  defp signal_source!(caller) do
    case Module.get_attribute(caller.module, :jido_ai_signal_source) do
      source when is_binary(source) -> source
      _other -> compile_error!(caller, caller.line, "ai must be used with Jido.AI.Agent")
    end
  end

  defp expressions({:__block__, _metadata, expressions}), do: expressions
  defp expressions(expression), do: [expression]

  defp expression_line({_name, metadata, _arguments}, fallback) when is_list(metadata),
    do: Keyword.get(metadata, :line, fallback)

  defp expression_line(_expression, fallback), do: fallback

  defp compile_error!(caller, line, description) do
    raise CompileError,
      file: caller.file,
      line: line || caller.line,
      description: description
  end
end
