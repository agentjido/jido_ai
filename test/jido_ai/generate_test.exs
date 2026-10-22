defmodule Jido.AI.GenerateTest do
  use ExUnit.Case, async: false

  import Mimic

  defmodule Assistant do
    use Jido.AI.Agent, name: "generate_test_assistant"

    ai do
      model :test_model
      instructions "Reply in one short sentence."
    end
  end

  defmodule Reply do
    use Jido.SignalAction,
      name: "generate_test_reply",
      description: "Defines a structured test reply",
      vsn: 1,
      input: [
        type: "test.generate.request",
        default_source: "/test/generate/client",
        schema: Zoi.object(%{question: Zoi.string()})
      ],
      output: [
        type: "test.generate.response",
        default_source: "/test/generate",
        schema: Zoi.object(%{answer: Zoi.string()})
      ]

    @impl Jido.Action
    def run(_params, _context), do: {:ok, %{answer: "Ready"}}
  end

  defmodule Echo do
    use Jido.Action,
      name: "generate_test_echo",
      description: "Echo one value",
      schema: Zoi.object(%{value: Zoi.string()})

    @impl Jido.Action
    def run(%{value: value}, _context), do: {:ok, %{value: value}}
  end

  defmodule ToolAssistant do
    use Jido.AI.Agent, name: "generate_test_tool_assistant"

    alias Jido.AI.GenerateTest.Echo

    ai do
      model :test_model

      tools do
        action Echo
      end
    end
  end

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{test_model: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "generates text with the resolved model and configured instructions" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      assert options[:temperature] == 0.0
      assert options[:receive_timeout] in 1..60_000

      assert [system, user] = ReqLLM.Context.to_list(context)
      assert %{role: :system, content: [%{type: :text, text: "Reply in one short sentence."}]} = system
      assert %{role: :user, content: [%{type: :text, text: "Are you ready?"}]} = user

      {:ok, response(model, context, "Ready")}
    end)

    assert Assistant.generate("Are you ready?", temperature: 0.0) == {:ok, "Ready"}
  end

  test "returns a ReqLLM error without changing it" do
    expect(ReqLLM, :generate_text, fn _model, _context, _options ->
      {:error, :provider_unavailable}
    end)

    assert Assistant.generate("Are you ready?") == {:error, :provider_unavailable}
  end

  test "respond requires prepared AI configuration" do
    assert Jido.AI.respond(%{}, "Are you ready?", reply: Reply) ==
             {:error, :missing_ai_config}
  end

  test "respond requires a Signal Action reply contract" do
    context = %{
      plugin_inputs: %{
        Jido.AI.Plugin => %Jido.Plugin.Input{prepared: Jido.AI.Plugin.config(Assistant)}
      }
    }

    assert Jido.AI.respond(context, "Are you ready?", reply: String) ==
             {:error, :invalid_reply_contract}
  end

  test "respond accepts ReqLLM structured output when application tools are present" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert [_tool] = options[:tools]
      assert %ReqLLM.Output{type: :object} = options[:output]

      output_call =
        ReqLLM.ToolCall.new(
          "structured-output",
          "structured_output",
          Jason.encode!(%{answer: "Ready"})
        )

      {:ok,
       %ReqLLM.Response{
         id: "structured-response",
         model: model,
         context: context,
         message: ReqLLM.Context.assistant("", tool_calls: [output_call]),
         finish_reason: :tool_calls,
         object: %{"answer" => "Ready"}
       }}
    end)

    context = %{
      plugin_inputs: %{
        Jido.AI.Plugin => %Jido.Plugin.Input{prepared: Jido.AI.Plugin.config(ToolAssistant)}
      }
    }

    assert Jido.AI.respond(context, "Are you ready?", reply: Reply) ==
             {:ok, %{answer: "Ready"}}
  end

  defp response(model, context, text) do
    %ReqLLM.Response{
      id: "test-response",
      model: model,
      context: context,
      message: ReqLLM.Context.assistant(text)
    }
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
