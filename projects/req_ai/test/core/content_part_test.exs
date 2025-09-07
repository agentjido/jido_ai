defmodule ReqLLM.ContentPartTest do
  use ExUnit.Case, async: true

  import ReqLLM.Test.{Factory, Macros}

  alias ReqLLM.ContentPart

  doctest ContentPart

  describe "constructors" do
    test "creates text content part" do
      part = ContentPart.text("Hello, world!")
      assert_struct(part, ContentPart, type: :text, text: "Hello, world!", metadata: nil)
    end

    test "creates image URL content part" do
      part = ContentPart.image_url("https://example.com/image.png")

      assert_struct(part, ContentPart,
        type: :image_url,
        url: "https://example.com/image.png",
        metadata: nil
      )
    end

    test "creates image data content part" do
      part = ContentPart.image_data(<<137, 80, 78, 71>>, "image/png")

      assert_struct(part, ContentPart,
        type: :image,
        data: <<137, 80, 78, 71>>,
        media_type: "image/png",
        metadata: nil
      )
    end

    test "creates file content part" do
      part = ContentPart.file(<<37, 80, 68, 70>>, "application/pdf", "document.pdf")

      assert_struct(part, ContentPart,
        type: :file,
        data: <<37, 80, 68, 70>>,
        media_type: "application/pdf",
        filename: "document.pdf",
        metadata: nil
      )
    end

    test "creates tool call content part" do
      part = ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})

      assert_struct(part, ContentPart,
        type: :tool_call,
        tool_call_id: "call_123",
        tool_name: "get_weather",
        input: %{location: "NYC"}
      )
    end

    test "creates tool result content part" do
      part = ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})

      assert_struct(part, ContentPart,
        type: :tool_result,
        tool_call_id: "call_123",
        tool_name: "get_weather",
        output: %{temperature: 72}
      )
    end
  end

  describe "validation" do
    test "validates content part types" do
      valid_parts = [
        text_part("Hello"),
        image_part("https://example.com/image.png"),
        ContentPart.image_data(<<137, 80, 78, 71>>, "image/png"),
        ContentPart.file(<<37, 80, 68, 70>>, "application/pdf", "doc.pdf"),
        tool_use_part("call_123", "get_weather", %{location: "NYC"}),
        tool_result_part("call_123", "get_weather", %{temperature: 72})
      ]

      for part <- valid_parts do
        assert ContentPart.valid?(part)
      end
    end

    test "rejects invalid content parts" do
      invalid_parts = [
        %ContentPart{type: :text, text: ""},
        ContentPart.image_url("invalid-url"),
        ContentPart.image_data(<<>>, "image/png"),
        %{type: :text, text: "Hello"},
        nil
      ]

      for part <- invalid_parts do
        refute ContentPart.valid?(part)
      end
    end

    test "validates media types" do
      valid_data = <<137, 80, 78, 71>>
      assert ContentPart.valid?(ContentPart.image_data(valid_data, "image/jpeg"))
      assert ContentPart.valid?(ContentPart.image_data(valid_data, "image/webp"))
      refute ContentPart.valid?(ContentPart.image_data(valid_data, "application/pdf"))

      valid_file_data = <<37, 80, 68, 70>>
      assert ContentPart.valid?(ContentPart.file(valid_file_data, "text/plain", "doc.txt"))
      refute ContentPart.valid?(ContentPart.file(valid_file_data, "invalid", "doc.pdf"))
    end

    test "validates tool constraints" do
      assert ContentPart.valid?(ContentPart.tool_result("call_123", "tool", "string output"))
      assert ContentPart.valid?(ContentPart.tool_result("call_123", "tool", 42))
      refute ContentPart.valid?(ContentPart.tool_call("", "get_weather", %{}))
      refute ContentPart.valid?(ContentPart.tool_result("call_123", "tool", nil))
    end
  end

  describe "serialization" do
    test "converts to map format" do
      assert ContentPart.to_map(text_part("Hello")) == %{type: "text", text: "Hello"}

      assert ContentPart.to_map(image_part("https://example.com/image.png")) ==
               %{type: "image_url", image_url: %{url: "https://example.com/image.png"}}

      expected = %{
        type: "tool_call",
        id: "call_123",
        function: %{name: "get_weather", arguments: Jason.encode!(%{location: "NYC"})}
      }

      assert ContentPart.to_map(tool_use_part("call_123", "get_weather", %{location: "NYC"})) ==
               expected
    end

    test "converts image data with base64 encoding" do
      data = <<137, 80, 78, 71>>
      result = ContentPart.to_map(ContentPart.image_data(data, "image/png"))
      assert %{type: "image_url", image_url: %{url: data_url}} = result
      assert String.starts_with?(data_url, "data:image/png;base64,")
    end
  end

  describe "provider_options" do
    test "extracts metadata correctly" do
      assert ContentPart.provider_options(text_part("Hello")) == %{}

      options = %{openai: %{image_detail: "high"}}
      part = text_part("Hello", metadata: %{provider_options: options})
      assert ContentPart.provider_options(part) == options

      part_no_options = text_part("Hello", metadata: %{other: "data"})
      assert ContentPart.provider_options(part_no_options) == %{}
    end
  end
end
