defmodule ReqLLM.Message.ContentPartTest do
  use ExUnit.Case, async: true
  alias ReqLLM.Message.ContentPart

  describe "text/1 and text/2" do
    test "creates text content part" do
      part = ContentPart.text("hello world")

      assert %ContentPart{type: :text, text: "hello world", metadata: %{}} = part
      assert part.url == nil
      assert part.data == nil
    end

    test "creates text with metadata" do
      metadata = %{lang: "en", source: "user"}
      part = ContentPart.text("hello", metadata)

      assert %ContentPart{type: :text, text: "hello", metadata: ^metadata} = part
    end

    test "handles empty string" do
      part = ContentPart.text("")
      assert part.text == ""
      assert part.type == :text
    end
  end

  describe "reasoning/1 and reasoning/2" do
    test "creates reasoning content part" do
      part = ContentPart.reasoning("thinking step")

      assert %ContentPart{type: :reasoning, text: "thinking step", metadata: %{}} = part
      assert part.tool_call_id == nil
    end

    test "creates reasoning with metadata" do
      metadata = %{step: 1}
      part = ContentPart.reasoning("first thought", metadata)

      assert %ContentPart{type: :reasoning, text: "first thought", metadata: ^metadata} = part
    end
  end

  describe "image_url/1" do
    test "creates image URL content part" do
      url = "https://example.com/image.jpg"
      part = ContentPart.image_url(url)

      assert %ContentPart{type: :image_url, url: ^url} = part
      assert part.data == nil
      assert part.media_type == nil
    end

    test "handles various URL formats" do
      urls = [
        "https://example.com/image.png",
        "http://localhost:3000/pic.gif",
        "data:image/png;base64,iVBOR..."
      ]

      for url <- urls do
        part = ContentPart.image_url(url)
        assert part.url == url
        assert part.type == :image_url
      end
    end
  end

  describe "image/2" do
    setup do
      %{
        png_data: <<137, 80, 78, 71, 13, 10, 26, 10>>,
        jpeg_data: <<255, 216, 255, 224>>
      }
    end

    test "creates image content part with default media type", %{png_data: data} do
      part = ContentPart.image(data)

      assert %ContentPart{type: :image, data: ^data, media_type: "image/png"} = part
      assert part.url == nil
      assert part.filename == nil
    end

    test "creates image with custom media type", %{jpeg_data: data} do
      part = ContentPart.image(data, "image/jpeg")

      assert %ContentPart{type: :image, data: ^data, media_type: "image/jpeg"} = part
    end

    test "handles empty binary data" do
      part = ContentPart.image(<<>>)
      assert part.data == <<>>
      assert part.media_type == "image/png"
    end
  end

  describe "file/3" do
    setup do
      %{
        file_data: "file contents here",
        filename: "test.txt"
      }
    end

    test "creates file content part with default media type", %{file_data: data, filename: name} do
      part = ContentPart.file(data, name)

      assert %ContentPart{
               type: :file,
               data: ^data,
               filename: ^name,
               media_type: "application/octet-stream"
             } = part
    end

    test "creates file with custom media type", %{file_data: data, filename: name} do
      part = ContentPart.file(data, name, "text/plain")

      assert %ContentPart{
               type: :file,
               data: ^data,
               filename: ^name,
               media_type: "text/plain"
             } = part
    end

    test "handles binary file data" do
      binary_data = <<1, 2, 3, 4, 5>>
      part = ContentPart.file(binary_data, "binary.dat", "application/binary")

      assert part.data == binary_data
      assert part.filename == "binary.dat"
      assert part.media_type == "application/binary"
    end
  end

  describe "tool_call/3" do
    test "creates tool call content part" do
      id = "call_123"
      name = "calculator"
      input = %{operation: "add", a: 1, b: 2}
      part = ContentPart.tool_call(id, name, input)

      assert %ContentPart{
               type: :tool_call,
               tool_call_id: ^id,
               tool_name: ^name,
               input: ^input
             } = part

      assert part.output == nil
    end

    test "handles various input types" do
      inputs = [
        %{key: "value"},
        ["item1", "item2"],
        "string input",
        42,
        nil
      ]

      for input <- inputs do
        part = ContentPart.tool_call("id", "tool", input)
        assert part.input == input
        assert part.type == :tool_call
      end
    end
  end

  describe "tool_result/2" do
    test "creates tool result content part" do
      id = "call_123"
      output = %{result: "success", value: 42}
      part = ContentPart.tool_result(id, output)

      assert %ContentPart{
               type: :tool_result,
               tool_call_id: ^id,
               output: ^output
             } = part

      assert part.input == nil
    end

    test "handles various output types" do
      outputs = [
        %{status: "ok"},
        ["result1", "result2"],
        "error message",
        {:ok, "value"},
        nil
      ]

      for output <- outputs do
        part = ContentPart.tool_result("id", output)
        assert part.output == output
        assert part.type == :tool_result
      end
    end
  end

  describe "struct validation and edge cases" do
    test "requires type field" do
      assert_raise ArgumentError, fn ->
        struct!(ContentPart, %{})
      end
    end

    test "accepts valid content types" do
      valid_types = [:text, :image_url, :image, :file, :tool_call, :tool_result, :reasoning]

      for type <- valid_types do
        part = struct!(ContentPart, %{type: type})
        assert part.type == type
      end
    end

    test "has proper default values" do
      part = struct!(ContentPart, %{type: :text})

      assert part.text == nil
      assert part.url == nil
      assert part.data == nil
      assert part.media_type == nil
      assert part.filename == nil
      assert part.tool_call_id == nil
      assert part.tool_name == nil
      assert part.input == nil
      assert part.output == nil
      assert part.metadata == %{}
    end
  end

  describe "Inspect implementation" do
    test "inspects text content part" do
      part = ContentPart.text("Hello world")
      output = inspect(part)

      assert output =~ "#ContentPart<"
      assert output =~ "text"
      assert output =~ "Hello world"
    end

    test "inspects reasoning content part" do
      part = ContentPart.reasoning("I think...")
      output = inspect(part)

      assert output =~ "#ContentPart<"
      assert output =~ "reasoning"
      assert output =~ "I think..."
    end

    test "truncates long text content" do
      long_text = String.duplicate("a", 50)
      part = ContentPart.text(long_text)
      output = inspect(part)

      truncated_part = String.slice(long_text, 0, 30)
      assert output =~ "#{truncated_part}..."
      assert String.length(truncated_part) == 30
      refute String.length(output) > 100
    end

    test "inspects image_url content part" do
      part = ContentPart.image_url("https://example.com/pic.jpg")
      output = inspect(part)

      assert output =~ "#ContentPart<"
      assert output =~ "image_url"
      assert output =~ "url: https://example.com/pic.jpg"
    end

    test "inspects image content part" do
      data = <<1, 2, 3, 4, 5>>
      part = ContentPart.image(data, "image/jpeg")
      output = inspect(part)

      assert output =~ "#ContentPart<"
      assert output =~ "image"
      assert output =~ "image/jpeg (5 bytes)"
    end

    test "inspects file content part" do
      data = "file content"
      part = ContentPart.file(data, "test.txt", "text/plain")
      output = inspect(part)

      assert output =~ "#ContentPart<"
      assert output =~ "file"
      assert output =~ "text/plain (12 bytes)"
    end

    test "inspects file content part with nil data" do
      part = struct!(ContentPart, %{type: :file, data: nil, media_type: "text/plain"})
      output = inspect(part)

      assert output =~ "text/plain (0 bytes)"
    end

    test "inspects tool_call content part" do
      part = ContentPart.tool_call("call_123", "calculator", %{op: "add"})
      output = inspect(part)

      assert output =~ "#ContentPart<"
      assert output =~ "tool_call"
      assert output =~ "call_123 calculator"
      assert output =~ "%{op: \"add\"}"
    end

    test "inspects tool_result content part" do
      part = ContentPart.tool_result("call_123", {:ok, 42})
      output = inspect(part)

      assert output =~ "#ContentPart<"
      assert output =~ "tool_result"
      assert output =~ "call_123 -> {:ok, 42}"
    end

    test "handles nil text in inspect" do
      part = struct!(ContentPart, %{type: :text, text: nil})
      output = inspect(part)

      assert output =~ "nil"
    end
  end
end
