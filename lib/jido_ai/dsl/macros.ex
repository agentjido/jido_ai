defmodule Jido.AI.DSL.Macros do
  @moduledoc false
  alias Jido.Action.Inline

  defmacro ai(id, do: block) do
    register_api!(__CALLER__)

    quote do
      ai_profile(unquote(id), do: unquote(block))
    end
  end

  def ai(id), do: Jido.AI.Authoring.ai(id)

  defmacro instructions(pattern, options) do
    inline_instructions(pattern, options, __CALLER__)
  end

  defmacro instructions(pattern, options, body) do
    inline_instructions(pattern, options ++ body, __CALLER__)
  end

  defp inline_instructions(pattern, options, caller) do
    unless Keyword.keyword?(options), do: error!(caller, "inline instructions require options")

    parsed = Inline.parse_callback!(pattern, options, caller)

    identity =
      quote do
        [host: Jido.AI.DSL, declaration: unquote(caller.line), role: :instructions]
      end

    compiled =
      Inline.compile!(identity, parsed, caller,
        default_name: "ai_instructions",
        remove_imports: [{__MODULE__, [instructions: 2, instructions: 3]}]
      )

    setter = Jido.AI.DSL.Agent.AiProfile.Options

    quote line: caller.line do
      unquote(compiled.declaration_ast)
      require unquote(setter)
      unquote(setter).instructions(unquote(compiled.target_ast))
    end
  end

  defmacro action(name, pattern, options) do
    inline_action(name, pattern, options, __CALLER__)
  end

  defmacro action(name, pattern, options, body) do
    inline_action(name, pattern, options ++ body, __CALLER__)
  end

  defp inline_action(name, pattern, options, caller) do
    unless is_atom(name) and name not in [nil, true, false],
      do: error!(caller, "inline Action name must be an atom")

    unless Keyword.keyword?(options), do: error!(caller, "inline Action requires options")

    {action_options, tool_options} =
      Keyword.split(options, [:do, :name, :description, :schema, :output_schema, :context])

    parsed =
      Inline.parse_callback!(
        pattern,
        Keyword.put_new(action_options, :name, Atom.to_string(name)),
        caller
      )

    identity =
      quote do
        [host: Jido.AI.DSL, declaration: unquote(name), line: unquote(caller.line), role: :action]
      end

    compiled =
      Inline.compile!(identity, parsed, caller,
        default_name: Atom.to_string(name),
        remove_imports: [{__MODULE__, [action: 3, action: 4]}]
      )

    entity = Jido.AI.DSL.Agent.AiProfile.Tools.Action
    tool_options = Keyword.put_new(tool_options, :as, name)

    quote line: caller.line do
      unquote(compiled.declaration_ast)
      require unquote(entity)
      unquote(entity).action(unquote(compiled.target_ast), unquote(tool_options))
    end
  end

  defp register_api!(caller) do
    unless Module.get_attribute(caller.module, :jido_ai_api_registered) do
      Module.put_attribute(caller.module, :jido_ai_api_registered, true)
      Module.put_attribute(caller.module, :before_compile, Jido.AI.DSL.Compiler)
    end
  end

  defp error!(caller, description),
    do: raise(CompileError, file: caller.file, line: caller.line, description: description)
end
