defmodule Jido.AI.Flow.Extension do
  @moduledoc """
  Adds AI authoring helpers to the Jido Flow module DSL.

  Each helper expands to normal Flow declarations. It does not add a component
  type or runtime. Add this module to a Flow's `:extensions` list.

      use Jido.Flow,
        name: "answer_turn",
        extensions: [Jido.AI.Flow.Extension]

      flow do
        step "prepare",
          action: Jido.AI.Actions.PrepareTurn,
          params: %{state_key: :thread}

        reason "answer",
          prompt: input(:question),
          reply: Ask,
          needs: ["prepare"]

        step "commit",
             [
               answer <- result("answer", :output),
               state_key <- result("prepare", :state_key)
             ],
             inline: [
               description: "Complete one typed AI turn",
               schema: Zoi.object(%{answer: Ask.output_schema(), state_key: Zoi.atom()}),
               context: context
             ] do
          Jido.AI.Turn.complete(context, Ask, answer, state_key: state_key)
        end

        output result("commit")
      end
  """

  use Jido.Flow.Extension

  @doc "Adds the configured AI reasoning Flow as one normal Flow Step."
  defmacro reason(name, options) do
    options = reason_options!(options, __CALLER__)
    prompt = Keyword.fetch!(options, :prompt)
    reply = reply_module!(Keyword.fetch!(options, :reply), __CALLER__)
    conversation = Keyword.get(options, :conversation)
    request_options = Keyword.get(options, :request_options, [])
    needs = Keyword.get(options, :needs, [])

    quote do
      step unquote(name),
        action: Jido.AI.Flow.Reason,
        needs: unquote(needs),
        params: %{
          input: unquote(prompt),
          reply: unquote(reply),
          conversation: unquote(conversation),
          request_options: unquote(request_options)
        }
    end
  end

  defp reason_options!(options, caller) do
    validate_options!(options, [:prompt, :reply], [:conversation, :request_options, :needs], "reason", caller)
  end

  defp validate_options!(options, required, optional, macro_name, caller) do
    allowed = required ++ optional

    unless Keyword.keyword?(options) and Enum.uniq(Keyword.keys(options)) == Keyword.keys(options) do
      compile_error!(caller, "#{macro_name} requires unique keyword options")
    end

    unknown = Keyword.keys(options) -- allowed
    if unknown != [], do: compile_error!(caller, "Unknown #{macro_name} options: #{inspect(unknown)}")

    missing = required -- Keyword.keys(options)
    if missing != [], do: compile_error!(caller, "Missing #{macro_name} options: #{inspect(missing)}")

    options
  end

  defp compile_error!(caller, description) do
    raise CompileError,
      file: caller.file,
      line: caller.line,
      description: description
  end

  defp reply_module!(reply, caller) do
    case Macro.expand(reply, caller) do
      module when is_atom(module) and module not in [nil, true, false] -> module
      _other -> compile_error!(caller, "reason :reply must be a literal module")
    end
  end
end
