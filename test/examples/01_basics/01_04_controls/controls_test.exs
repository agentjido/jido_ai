defmodule JidoAI.Examples.ControlsTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias JidoAI.Examples.Controls.Agent

  @moduletag :example

  @tag capture_log: true
  test "an input control can stop the request" do
    reject(ReqLLM, :generate_text, 3)

    assert {:error, error} = Agent.generate("Private question", jido_context: %{role: :guest})
    assert Exception.message(error) == "access_denied"
  end

  test "an output control checks the generated text" do
    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok, text_response(model, context, "Answer [source]", id: "controls-example")}
    end)

    assert Agent.generate("Member question", jido_context: %{role: :member}) ==
             {:ok, "Answer [source]"}
  end

  test "the inline output control is an ordinary Jido Action" do
    action = Jido.AI.Plugin.config(Agent).controls.output

    assert action.__jido_authoring_kind__() == :action
    assert action.name() == "require_source"
    assert function_exported?(action, :__jido_inline_action__, 0)
  end

  @tag capture_log: true
  test "an output control can reject the generated text" do
    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok, text_response(model, context, "Answer without evidence", id: "controls-example")}
    end)

    assert {:error, error} = Agent.generate("Member question", jido_context: %{role: :member})
    assert Exception.message(error) == "source_required"
  end
end
