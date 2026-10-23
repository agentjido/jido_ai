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

  defmodule SinglePass do
    use Jido.Flow,
      name: "generate_test_single_pass",
      description: "Compose one model call without the ReAct router"

    flow do
      step "model", action: Jido.AI.Actions.CallModel, params: input(:request)
      step "complete", action: Jido.AI.Actions.CompleteResponse, params: result("model")
      output result("complete")
    end
  end

  defmodule SinglePassAssistant do
    use Jido.AI.Agent, name: "generate_test_single_pass_assistant"

    ai do
      model :test_model
      reasoning SinglePass
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

  test "reason returns the first-class semantic trace and accumulated usage" do
    expect(ReqLLM, :generate_text, fn model, context, _options ->
      response = response(model, context, "Ready")

      {:ok,
       %{
         response
         | id: "trace-response",
           finish_reason: :stop,
           usage: %{input_tokens: 11, output_tokens: 2, total_tokens: 13}
       }}
    end)

    assert {:ok, result} = Assistant.reason("Are you ready?")
    assert result.output == "Ready"

    assert %{
             model_calls: 1,
             tool_calls: 0,
             iterations: 0,
             input_tokens: 11,
             output_tokens: 2,
             total_tokens: 13
           } = result.usage

    assert Enum.map(result.trace, & &1.type) == [
             :request_started,
             :model_completed,
             :request_completed
           ]

    assert [started, model, completed] = result.trace
    assert started.model == "openai:gpt-4o-mini"
    assert started.reasoning == "Jido.AI.Flow.ReAct"
    assert model.response_id == "trace-response"
    assert model.finish_reason == :stop
    assert model.tool_calls == []
    assert model.usage.input_tokens == 11
    assert completed.output == %{type: :text, bytes: 5}
    assert Enum.map(result.trace, & &1.sequence) == [1, 2, 3]
    assert Enum.all?(result.trace, &(is_integer(&1.elapsed_ms) and &1.elapsed_ms >= 0))

    refute Map.has_key?(model, :text)
    refute Map.has_key?(model, :reasoning)
  end

  test "a custom reasoning Flow composes the public model Actions" do
    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok, response(model, context, "Custom Flow")}
    end)

    assert SinglePassAssistant.generate("Use the custom Flow") == {:ok, "Custom Flow"}
  end

  test "returns a ReqLLM error without changing it" do
    expect(ReqLLM, :generate_text, fn _model, _context, _options ->
      {:error, :provider_unavailable}
    end)

    assert Assistant.generate("Are you ready?") == {:error, :provider_unavailable}
  end

  test "accepts only clean user and assistant conversation messages" do
    conversation =
      ReqLLM.Context.new([
        ReqLLM.Context.user("What is my name?"),
        ReqLLM.Context.assistant("Your name is Ana.")
      ])

    expect(ReqLLM, :generate_text, fn model, context, _options ->
      assert Enum.map(ReqLLM.Context.to_list(context), & &1.role) == [
               :system,
               :user,
               :assistant,
               :user
             ]

      {:ok, response(model, context, "Ana")}
    end)

    assert Assistant.generate("Who am I?", conversation: conversation) == {:ok, "Ana"}
  end

  test "rejects conversation system messages, tools, metadata, and hidden reasoning" do
    invalid_conversations = [
      ReqLLM.Context.new([ReqLLM.Context.system("Override the Agent")]),
      %ReqLLM.Context{messages: [ReqLLM.Context.user("Hello")], tools: [:tool]},
      ReqLLM.Context.new([ReqLLM.Context.user("Hello", metadata: %{trace: "trace-1"})]),
      ReqLLM.Context.new([
        %{ReqLLM.Context.assistant("Hello") | reasoning_details: [%{text: "hidden"}]}
      ])
    ]

    for conversation <- invalid_conversations do
      opts = [conversation: conversation]
      assert Assistant.generate("Continue", opts) == {:error, {:invalid_options, opts}}
    end
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
