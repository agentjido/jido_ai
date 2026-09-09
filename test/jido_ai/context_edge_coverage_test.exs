defmodule Jido.AI.ContextEdgeCoverageTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias Jido.AI.Context
  alias Jido.AI.Context.Entry
  alias ReqLLM.Message.ContentPart

  test "debug and pretty views cover truncation and tool-call shapes" do
    context = %Context{
      id: "debug",
      system_prompt: String.duplicate("s", 70),
      entries: [
        %Entry{role: :custom, content: %{large: String.duplicate("x", 20)}},
        %Entry{role: :tool, name: "lookup", content: [1, 2], tool_call_id: "call"},
        %Entry{
          role: :assistant,
          content: nil,
          tool_calls: [%{name: "atom"}, %{"name" => "string"}, %{bad: true}]
        },
        %Entry{role: :assistant, content: "plain", tool_calls: []},
        %Entry{role: :user, content: String.duplicate("u", 20)},
        %Entry{role: :system, content: "entry system"}
      ]
    }

    view = Context.debug_view(context, last: 3, truncate: 5)
    assert view.length == 6
    assert length(view.entries) == 3
    assert view.system_prompt == "sssss..."

    all = Context.debug_view(context, last: :invalid, truncate: 5)
    assert length(all.entries) == 6
    assert Enum.any?(all.entries, &(&1[:tool_calls] == ["atom", "string", "unknown"]))

    output = capture_io(fn -> assert :ok = Context.pp(context) end)
    assert output =~ "[system]"
    assert output =~ "<tool: atom, string, ?>"
    assert output =~ "[tool]"
    assert output =~ "[custom]"
  end

  test "coerce rejects invalid containers and preserves valid contexts" do
    context = Context.new(id: "existing")
    assert Context.coerce(context) == {:ok, context}
    assert Context.coerce(%URI{}) == :error
    assert Context.coerce(%{id: 1, entries: []}) == :error
    assert Context.coerce(%{id: "id", entries: :bad}) == :error
    assert Context.coerce(:bad) == :error
  end

  test "imported histories normalize all supported content-part forms" do
    messages = [
      %{
        role: "user",
        content: [
          "plain",
          %{type: :text, text: "atom text", metadata: %{source: :atom}},
          %{"type" => "text", "text" => nil},
          %{type: :thinking, thinking: "thought"},
          %{"type" => "image_url", "url" => "https://example.com/image.png"},
          %{type: :image, data: "png", media_type: "image/png"},
          %{type: :image, data: "png", metadata: %{detail: :high}},
          %{type: :image},
          %{type: :file, source: [file_id: " file_1 "], title: "Report"},
          %{"type" => "file", "data" => "DATA", "filename" => " report.txt "},
          %{type: :file, data: "DATA"},
          %{"type" => "unknown"},
          42
        ]
      },
      %{
        role: "assistant",
        content: [
          %{"type" => "thinking", "text" => "private"},
          %{"type" => "text", "text" => "public"}
        ]
      },
      %{role: "developer", content: "developer note", refs: []},
      %{role: "function", content: "function output", refs: %{source: "call"}},
      %{role: "custom", content: "custom output"}
    ]

    context = Context.new(id: "imported") |> Context.append_messages(messages)
    projected = Context.to_messages(context)

    assert [%{role: :user, content: user_parts}, assistant, developer, function, custom] = projected
    assert Enum.any?(user_parts, &match?(%ContentPart{type: :thinking}, &1))
    assert Enum.any?(user_parts, &match?(%ContentPart{type: :image}, &1))
    assert Enum.any?(user_parts, &match?(%ContentPart{type: :file}, &1))

    assert assistant.content == [
             %{type: :thinking, thinking: "private"},
             %{type: :text, text: "public"}
           ]

    refute Map.has_key?(assistant, :reasoning_details)
    assert developer.role == :developer
    refute Map.has_key?(developer, :refs)
    assert function.role == :function
    assert function.refs == %{source: "call"}
    assert custom.role == "custom"
  end

  test "assistant projection prepends thinking to binary and list content" do
    context =
      Context.new()
      |> Context.append_assistant("answer", nil, thinking: "reason")
      |> Context.append_assistant([ContentPart.text("answer")], nil, thinking: "reason")

    [binary, list] = Context.to_messages(context)
    assert [%{type: :thinking}, %{type: :text}] = binary.content
    assert [%{type: :thinking}, %ContentPart{type: :text}] = list.content
  end

  test "inspect handles string-key and unknown entry roles in a manually restored context" do
    assert inspect(%Context{id: "map", entries: [%{"role" => "user"}, %{bad: true}]}) =~
             "last: [:unknown, \"user\"]"

    assert inspect(%Context{id: "truncated", entries: %{type: :list, size: 12}}) ==
             "#Context<12 entries, truncated>"

    assert inspect(%Context{id: "unknown", entries: :invalid}) == "#Context<unknown entries>"
  end
end
