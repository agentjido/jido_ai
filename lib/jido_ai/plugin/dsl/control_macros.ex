defmodule Jido.AI.Plugin.DSL.ControlMacros do
  @moduledoc false

  alias Jido.Action.Inline

  defmacro input(options, body) when is_list(options) and is_list(body) do
    compile_control(:input, nil, options ++ body, __CALLER__)
  end

  defmacro input(pattern, options) when is_list(options) do
    compile_control(:input, pattern, options, __CALLER__)
  end

  defmacro input(pattern, options, body) when is_list(options) and is_list(body) do
    compile_control(:input, pattern, options ++ body, __CALLER__)
  end

  defmacro output(options, body) when is_list(options) and is_list(body) do
    compile_control(:output, nil, options ++ body, __CALLER__)
  end

  defmacro output(pattern, options) when is_list(options) do
    compile_control(:output, pattern, options, __CALLER__)
  end

  defmacro output(pattern, options, body) when is_list(options) and is_list(body) do
    compile_control(:output, pattern, options ++ body, __CALLER__)
  end

  defp compile_control(stage, pattern, options, caller) do
    parsed = Inline.parse_callback!(pattern, options, caller)
    index = next_index(caller.module, stage)

    path = [
      host: Jido.AI.Plugin,
      stage: stage,
      declaration: index,
      role: :action
    ]

    compiled =
      Inline.compile!(Macro.escape(path), parsed, caller,
        default_name: "jido_ai_#{stage}_control_#{index}",
        remove_imports: [
          {__MODULE__, [input: 2, input: 3, output: 2, output: 3]}
        ]
      )

    control_call = {stage, [line: caller.line], [compiled.target_ast]}

    quote generated: true do
      unquote(compiled.declaration_ast)
      unquote(control_call)
    end
  end

  defp next_index(owner, stage) do
    attribute = :jido_ai_inline_control_counts
    counts = Module.get_attribute(owner, attribute) || %{}
    index = Map.get(counts, stage, 0) + 1
    Module.put_attribute(owner, attribute, Map.put(counts, stage, index))
    index
  end
end
