defmodule Jido.AI.TurnEdgeCoverageTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Turn
  alias Jido.AI.Turn.Content
  alias ReqLLM.Message.ContentPart
  alias ReqLLM.ToolResult

  defmodule Echo do
    use Jido.Action, name: "turn_edge_echo", schema: Zoi.object(%{})
    def run(_params, _context), do: {:ok, %{status: :done}}
  end

  defmodule BrokenSchema do
    def name, do: "broken_schema"
    def schema, do: raise("broken schema")
  end

  defmodule ThrowingSchema do
    def name, do: "throwing_schema"
    def schema, do: throw(:broken_schema)
  end

  test "preserves existing turns and can override their model" do
    turn = %Turn{text: "done", model: "old"}
    assert Turn.from_response(turn) == turn
    assert Turn.from_response(turn, model: "new").model == "new"
    assert Turn.from_result_map(turn) == turn
  end

  test "normalizes result-map types and finish reasons" do
    assert Turn.from_result_map(%{type: "tool_calls"}).type == :tool_calls
    assert Turn.from_result_map(%{type: "unknown"}).type == :final_answer

    expected = %{
      "stop" => :stop,
      "completed" => :stop,
      "tool_calls" => :tool_calls,
      "tool_use" => :tool_calls,
      "length" => :length,
      "max_tokens" => :length,
      "max_output_tokens" => :length,
      "content_filter" => :content_filter,
      "end_turn" => :stop,
      "error" => :error,
      "cancelled" => :cancelled,
      "incomplete" => :incomplete,
      "unknown" => :unknown,
      "provider-specific" => :unknown
    }

    for {input, output} <- expected do
      assert Turn.from_result_map(%{finish_reason: input}).finish_reason == output
    end
  end

  test "handles malformed content and extraction fallbacks" do
    assert Turn.extract_text(%{message: %{content: false}}) == ""
    assert Turn.extract_text(%{choices: [%{message: %{content: false}}]}) == ""
    assert Turn.extract_text(%{content: [%{type: :text, text: "direct"}]}) == "direct"
    assert Turn.extract_text(%{other: true}) == ""
    assert Turn.extract_text(["io", ["data"]]) == "iodata"
    assert Turn.extract_text([%{type: :image, url: "x"}]) == ""
    assert Turn.extract_text(17) == ""

    assert Turn.extract_from_content([%{type: :text, text: "one"}, %{type: "text", text: "two"}, :bad]) ==
             "one\ntwo"

    assert Turn.extract_from_content(:bad) == ""

    assert Turn.extract_from_content([%{type: :text, text: 17}]) == ""
  end

  test "handles stream chunks that do not contain content parts" do
    assert Turn.stream_content_part(:bad) == :error
    assert Turn.content_parts_from_chunks([:bad]) == []

    turn = %Turn{content_parts: :invalid, text: "fallback"}
    assert Turn.assistant_content(turn) == "fallback"
    assert Turn.result(turn) == "fallback"
  end

  test "builds a map from one Action module" do
    assert Jido.AI.ToolAdapter.to_action_map(Echo) == %{Echo.name() => Echo}
  end

  test "runs calls even when the response type was not classified as tool calls" do
    turn = %Turn{
      type: :final_answer,
      tool_calls: [%{id: "call", name: Echo.name(), arguments: %{}}]
    }

    assert {:ok, updated} = Jido.AI.Tools.Executor.run_tools(turn, :invalid_context, tools: Echo, timeout: :invalid)
    assert [%{raw_result: {:ok, %{status: :done}, []}}] = updated.tool_results
  end

  test "normalizes malformed tool calls and result content shapes" do
    turn = Turn.from_result_map(%{tool_calls: :invalid, tool_results: :invalid})
    assert turn.tool_calls == []
    assert turn.tool_results == []

    assert %{tool_calls: [:invalid]} = Turn.from_result_map(%{tool_calls: [:invalid]})

    canonical = Jason.encode!(%{ok: true, result: 1})

    turn =
      Turn.with_tool_results(%Turn{}, [
        %{id: "canonical", name: "tool", content: canonical},
        %{id: "plain", name: "tool", content: "plain", raw_result: {:ok, :value}},
        %{id: "parts", name: "tool", content: [ContentPart.text("part")]},
        %{id: "list", name: "tool", content: [1, 2]},
        %{id: "nil", name: "tool", content: nil, raw_result: {:error, :bad}},
        %{id: "empty-map", name: "tool", content: %{}},
        %{id: "map", name: "tool", content: %{value: 1}},
        %{id: "other", name: "tool", content: 17, raw_result: {:ok, :fallback}},
        :raw
      ])

    assert Enum.at(turn.tool_results, 0).content == canonical
    assert [%ContentPart{type: :text}] = Enum.at(turn.tool_results, 2).content
    assert Enum.all?(turn.tool_results, &match?(%{raw_result: {_, _, _}}, &1))

    assert length(Turn.tool_messages(turn)) == 9
  end

  test "normalizes string thinking blocks and tool argument variants" do
    thinking_turn =
      Turn.from_response(%{
        message: %{content: [%{type: "thinking", thinking: "private"}]}
      })

    assert thinking_turn.thinking_content == "private"

    turn =
      Turn.from_result_map(%{
        text: 17,
        tool_calls: [
          %{id: "valid", name: "echo", arguments: ~s({"value":1})},
          %{id: "invalid", name: "echo", arguments: "not-json"},
          %{id: "other", name: "echo", arguments: [:invalid]}
        ]
      })

    assert turn.text == ""
    assert Enum.map(turn.tool_calls, & &1.arguments) == [%{"value" => 1}, %{}, %{}]

    message = Turn.assistant_message(%{turn | type: :final_answer})
    assert length(message.tool_calls) == 3
  end

  test "executes a valid module without an explicit timeout" do
    assert {:ok, %{status: :done}, []} = Jido.AI.Tools.Executor.execute_module(Echo, %{}, %{}, timeout: nil)
  end

  test "returns normalized errors when tool setup raises or throws" do
    assert {:error, raised, []} = Jido.AI.Tools.Executor.execute_module(BrokenSchema, %{}, %{}, timeout: nil)
    assert raised.type == :exception
    assert raised.message == "broken schema"

    assert {:error, thrown, []} = Jido.AI.Tools.Executor.execute_module(ThrowingSchema, %{}, nil)
    assert thrown.type == :caught
    assert thrown.message == "Caught throw: :broken_schema"
  end

  test "formats invalid envelopes and basic payload variants" do
    assert %{"ok" => false, "error" => %{"type" => "invalid_result"}} =
             Content.format_tool_result_content(:invalid) |> Jason.decode!()

    assert %{"ok" => true, "result" => [1, 2]} =
             Content.format_tool_result_content({:ok, [1, 2]}) |> Jason.decode!()

    assert %{"ok" => true, "result" => nil} =
             Content.format_tool_result_content({:ok, nil}) |> Jason.decode!()

    result = %ToolResult{output: nil, content: [ContentPart.text("visible")], metadata: %{tag: "x"}}

    [%ContentPart{text: encoded}, %ContentPart{type: :text, text: "visible"}] =
      Content.format_tool_result_content({:ok, result, []})

    assert Jason.decode!(encoded)["result"] == %{
             "content" => [%{"type" => "text", "text" => "visible"}],
             "metadata" => %{"tag" => "x"}
           }
  end

  test "normalizes all supported content-part map forms" do
    assert Content.normalize_content_parts(nil) == []
    assert Content.normalize_content_parts("text") == [ContentPart.text("text")]
    assert [%ContentPart{type: :text, text: ":other"}] = Content.normalize_content_parts(:other)

    parts =
      Content.normalize_content_parts([
        "plain",
        %{type: :text, text: "text", metadata: %{a: 1}},
        %{"type" => "text", "text" => 17},
        %{type: :thinking, text: "thought"},
        %{type: :image_url, url: "https://example.test/image", metadata: %{a: 1}},
        %{type: :image, data: <<1>>, media_type: "image/gif"},
        %{type: :image, data: <<2>>, metadata: %{a: 1}},
        %{type: :image, data: nil},
        %{type: :unknown},
        17
      ])

    assert Enum.map(parts, & &1.type) == [
             :text,
             :text,
             :text,
             :thinking,
             :image_url,
             :image,
             :image,
             :text,
             :text,
             :text
           ]
  end

  test "normalizes file maps from direct and nested fields" do
    [file_id, file_data, invalid] =
      Content.normalize_content_parts([
        %{
          type: :file_id,
          source: [file_id: " provider-file ", title: "Guide"],
          filename: "guide.pdf",
          metadata: [purpose: "test"]
        },
        %{
          "type" => "document",
          "source" => %{
            "data" => <<1, 2>>,
            "filename" => "raw.bin",
            "media_type" => "application/test"
          },
          "metadata" => [:not_keyword],
          "citations" => ["one"]
        },
        %{type: :file, file_id: " ", data: 17, source: :invalid}
      ])

    assert %ContentPart{type: :file, file_id: "provider-file", filename: "guide.pdf"} = file_id
    assert file_id.metadata == %{purpose: "test", title: "Guide"}

    assert %ContentPart{type: :file, data: <<1, 2>>, filename: "raw.bin"} = file_data
    assert file_data.metadata == %{}
    assert %ContentPart{type: :text} = invalid
  end

  test "recognizes content-part lists without accepting partial matches" do
    assert Content.content_parts_list?([ContentPart.text("x")])
    assert Content.content_parts_list?([%{type: :document}])
    assert Content.content_parts_list?([%{"type" => "file_id"}])
    refute Content.content_parts_list?([])
    refute Content.content_parts_list?([%{type: :unknown}])
    refute Content.content_parts_list?(:invalid)
  end
end
