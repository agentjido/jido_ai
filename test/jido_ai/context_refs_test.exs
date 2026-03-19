defmodule JidoAI.ContextRefsTest do
  @moduledoc """
  Tests that refs survive Context entry creation and to_messages projection.
  """
  use ExUnit.Case, async: true

  alias Jido.AI.Context

  describe "refs on Context.Entry" do
    test "to_messages preserves refs on user messages" do
      ctx =
        Context.new()
        |> Context.append_user("hello", refs: %{slack_ts: "1234.000"})

      [msg] = Context.to_messages(ctx)

      assert msg.role == :user
      assert msg.content == "hello"
      assert msg.refs == %{slack_ts: "1234.000"}
    end

    test "to_messages preserves refs on assistant messages" do
      ctx =
        Context.new()
        |> Context.append_assistant("hi there", nil, refs: %{slack_ts: "1234.001"})

      [msg] = Context.to_messages(ctx)

      assert msg.role == :assistant
      assert msg.refs == %{slack_ts: "1234.001"}
    end

    test "to_messages preserves refs on tool messages" do
      ctx =
        Context.new()
        |> Context.append_tool_result("tc_1", "calculator", ~s({"result": 3}), refs: %{signal_id: "evt_3"})

      [msg] = Context.to_messages(ctx)

      assert msg.role == :tool
      assert msg.tool_call_id == "tc_1"
      assert msg.refs == %{signal_id: "evt_3"}
    end

    test "to_messages omits refs key when nil" do
      ctx =
        Context.new()
        |> Context.append_user("hello")

      [msg] = Context.to_messages(ctx)

      refute Map.has_key?(msg, :refs)
    end

    test "refs survive append and retrieval round-trip" do
      ctx =
        Context.new()
        |> Context.append_user("msg1", refs: %{slack_ts: "1.0"})
        |> Context.append_assistant("msg2", nil, refs: %{slack_ts: "2.0"})
        |> Context.append_user("msg3", refs: %{slack_ts: "3.0"})

      msgs = Context.to_messages(ctx)

      assert Enum.map(msgs, & &1[:refs]) == [
               %{slack_ts: "1.0"},
               %{slack_ts: "2.0"},
               %{slack_ts: "3.0"}
             ]
    end

    test "mixed refs and no-refs entries" do
      ctx =
        Context.new()
        |> Context.append_user("a", refs: %{slack_ts: "1.0"})
        |> Context.append_assistant("b", nil)
        |> Context.append_user("c", refs: %{slack_ts: "3.0"})

      msgs = Context.to_messages(ctx)
      refs = Enum.map(msgs, &Map.get(&1, :refs, :none))
      assert refs == [%{slack_ts: "1.0"}, :none, %{slack_ts: "3.0"}]
    end

    test "append_messages preserves refs from imported histories" do
      msgs = [
        %{role: :user, content: "hello", refs: %{slack_ts: "1.0"}},
        %{role: :assistant, content: "hi", refs: %{slack_ts: "2.0"}},
        %{
          role: :tool,
          tool_call_id: "tc_1",
          name: "calculator",
          content: ~s({"result": 3}),
          refs: %{signal_id: "evt_3"}
        }
      ]

      ctx = Context.new() |> Context.append_messages(msgs)

      assert Enum.map(Context.to_messages(ctx), &Map.get(&1, :refs)) == [
               %{slack_ts: "1.0"},
               %{slack_ts: "2.0"},
               %{signal_id: "evt_3"}
             ]
    end

    test "coerce preserves refs from serialized context entries" do
      raw = %{
        id: "ctx_1",
        entries: [
          %{
            role: :tool,
            tool_call_id: "tc_1",
            name: "calculator",
            content: ~s({"result": 3}),
            refs: %{signal_id: "evt_3"}
          },
          %{role: :user, content: "hello", refs: %{slack_ts: "1.0"}}
        ],
        system_prompt: "You are helpful."
      }

      assert {:ok, ctx} = Context.coerce(raw)

      assert Context.to_messages(ctx) == [
               %{role: :system, content: "You are helpful."},
               %{role: :user, content: "hello", refs: %{slack_ts: "1.0"}},
               %{
                 role: :tool,
                 tool_call_id: "tc_1",
                 name: "calculator",
                 content: ~s({"result": 3}),
                 refs: %{signal_id: "evt_3"}
               }
             ]
    end
  end
end
