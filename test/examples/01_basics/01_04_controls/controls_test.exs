defmodule JidoAI.Examples.ControlsTest do
  use ExUnit.Case, async: false

  import Mimic

  alias JidoAI.Examples.Controls.Agent

  @moduletag :example

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  @tag capture_log: true
  test "an input control can stop the request" do
    reject(ReqLLM, :generate_text, 3)

    assert {:error, error} = Agent.generate("Private question", jido_context: %{role: :guest})
    assert Exception.message(error) == "access_denied"
  end

  test "an output control checks the generated text" do
    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok, response(model, context, "Answer [source]")}
    end)

    assert Agent.generate("Member question", jido_context: %{role: :member}) ==
             {:ok, "Answer [source]"}
  end

  test "the inline output control is an ordinary Jido Action" do
    [action] = Jido.AI.Plugin.config(Agent).controls.output

    assert action.__jido_authoring_kind__() == :action
    assert action.name() == "require_source"
    assert function_exported?(action, :__jido_inline_action__, 0)
  end

  @tag capture_log: true
  test "an output control can reject the generated text" do
    expect(ReqLLM, :generate_text, fn model, context, _options ->
      {:ok, response(model, context, "Answer without evidence")}
    end)

    assert {:error, error} = Agent.generate("Member question", jido_context: %{role: :member})
    assert Exception.message(error) == "source_required"
  end

  defp response(model, context, text) do
    %ReqLLM.Response{
      id: "controls-example",
      model: model,
      context: context,
      message: ReqLLM.Context.assistant(text)
    }
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
