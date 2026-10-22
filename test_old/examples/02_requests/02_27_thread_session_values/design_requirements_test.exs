defmodule JidoAI.Examples.ThreadSessionValues.DesignRequirementsTest do
  use ExUnit.Case, async: true
  alias Jido.{Session, Thread}
  alias Jido.AI.Thread.Projection
  @moduletag :example
  @moduletag :design_requirement

  @tag requirements: ["VAL-REQ-002", "VAL-REQ-004", "VAL-REQ-022"]
  test "VAL-REQ-002 encoded Session rejects unknown keys without creating an atom" do
    document = Session.new() |> Session.encode() |> Jason.encode!() |> Jason.decode!()
    key = "untrusted_session_key_#{System.unique_integer([:positive])}"
    assert {:error, _} = Session.decode(Map.put(document, key, true))
    assert_raise ArgumentError, fn -> String.to_existing_atom(key) end
    assert {:error, :unsupported_version} = Session.decode(%{document | "version" => 999})
  end

  @tag requirements: ["VAL-REQ-009"]
  test "VAL-REQ-009 projection does not change the portable stored value" do
    {:ok, thread} = Projection.append(Thread.new(), [ReqLLM.Context.user("Question")])
    before = Thread.encode(thread)
    assert {:ok, [_]} = Projection.messages(thread)
    assert Thread.encode(thread) == before
  end

  @tag requirements: ["VAL-REQ-024"]
  test "VAL-REQ-024 default projection excludes an unresolved tool exchange" do
    message = ReqLLM.Context.assistant("", tool_calls: [ReqLLM.ToolCall.new("pending", "lookup", "{}")])
    {:ok, thread} = Projection.append(Thread.new(), [message])
    assert {:ok, messages} = Projection.messages(thread)
    assert messages == []
  end

  @tag requirements: ["VAL-REQ-007"]
  test "VAL-REQ-007 a multimodal summary excludes hidden thinking" do
    parts = [
      ReqLLM.Message.ContentPart.text("Visible question"),
      ReqLLM.Message.ContentPart.thinking("PRIVATE_SYNTHETIC_MARKER")
    ]

    summary = Jido.AI.Query.summarize(parts)
    assert summary =~ "Visible question"
    refute summary =~ "PRIVATE_SYNTHETIC_MARKER"
  end

  @tag requirements: ["OBS-REQ-024"]
  test "OBS-REQ-024 public transport sanitization accepts malformed and runtime values" do
    payload = %{
      password: "SYNTHETIC_SECRET",
      bytes: <<255, 0, 254>>,
      worker: self(),
      callback: fn -> :not_called end,
      reference: make_ref(),
      nested: Enum.reduce(1..20, "leaf", fn _, acc -> %{next: acc} end),
      text: String.duplicate("x", 100_000)
    }

    safe = Jido.AI.Observe.sanitize_transport_payload(payload, max_depth: 3, max_string_chars: 64)
    assert {:ok, encoded} = Jason.encode(safe)
    refute encoded =~ "SYNTHETIC_SECRET"
    assert byte_size(encoded) < 2_000
    assert :ok = Jido.Action.validate_static_data(safe)
  end
end
