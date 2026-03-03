defmodule Jido.AI.ThreadDeprecatedTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Jido.AI.Context, as: AIContext
  alias Jido.AI.Thread

  test "legacy thread API warns and preserves behavior" do
    log =
      capture_log(fn ->
        thread =
          Thread.new(system_prompt: "Legacy prompt")
          |> Thread.append_user("hello")
          |> Thread.append_assistant("hi")

        assert %Thread{} = thread

        assert [
                 %{role: :system, content: "Legacy prompt"},
                 %{role: :user, content: "hello"},
                 %{role: :assistant, content: "hi"}
               ] = Thread.to_messages(thread)
      end)

    assert log =~ "DEPRECATION: Jido.AI.Thread is deprecated; use Jido.AI.Context"
  end

  test "context coercion accepts legacy thread structs" do
    context =
      AIContext.new(system_prompt: "Ctx")
      |> AIContext.append_user("message")

    thread = Thread.from_context(context)

    assert {:ok, %AIContext{} = coerced} = AIContext.coerce(thread)
    assert AIContext.to_messages(coerced) == AIContext.to_messages(context)
  end
end
