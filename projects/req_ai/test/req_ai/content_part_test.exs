defmodule ReqAI.ContentPartTest do
  use ExUnit.Case, async: true

  alias ReqAI.ContentPart

  doctest ContentPart

  # 6 constructor tests (one per type)
  describe "constructors" do
    test "text/2 creates valid text content part" do
      part = ContentPart.text("Hello, world!")
      assert %ContentPart{type: :text, text: "Hello, world!", metadata: nil} = part
    end

    test "image_url/2 creates valid image URL content part" do
      url = "https://example.com/image.png"
      part = ContentPart.image_url(url)
      assert %ContentPart{type: :image_url, url: ^url, metadata: nil} = part
    end

    test "image_data/3 creates valid image data content part" do
      data = <<137, 80, 78, 71>>
      part = ContentPart.image_data(data, "image/png")
      assert %ContentPart{type: :image, data: ^data, media_type: "image/png", metadata: nil} = part
    end

    test "file/4 creates valid file content part" do
      data = <<37, 80, 68, 70>>
      part = ContentPart.file(data, "application/pdf", "document.pdf")
      assert %ContentPart{type: :file, data: ^data, media_type: "application/pdf", filename: "document.pdf", metadata: nil} = part
    end

    test "tool_call/4 creates valid tool call content part" do
      part = ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
      assert %ContentPart{type: :tool_call, tool_call_id: "call_123", tool_name: "get_weather", input: %{location: "NYC"}} = part
    end

    test "tool_result/4 creates valid tool result content part" do
      part = ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})
      assert %ContentPart{type: :tool_result, tool_call_id: "call_123", tool_name: "get_weather", output: %{temperature: 72}} = part
    end
  end

  # 4 validation tests (happy paths + failure cases)
  describe "validation" do
    test "valid?/1 validates all content part types successfully" do
      assert ContentPart.valid?(ContentPart.text("Hello"))
      assert ContentPart.valid?(ContentPart.image_url("https://example.com/image.png"))
      assert ContentPart.valid?(ContentPart.image_data(<<137, 80, 78, 71>>, "image/png"))
      assert ContentPart.valid?(ContentPart.file(<<37, 80, 68, 70>>, "application/pdf", "doc.pdf"))
      assert ContentPart.valid?(ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"}))
      assert ContentPart.valid?(ContentPart.tool_result("call_123", "get_weather", %{temperature: 72}))
    end

    test "valid?/1 rejects invalid content parts" do
      refute ContentPart.valid?(%ContentPart{type: :text, text: ""})
      refute ContentPart.valid?(ContentPart.image_url("invalid-url"))
      refute ContentPart.valid?(ContentPart.image_data(<<>>, "image/png"))
      refute ContentPart.valid?(%{type: :text, text: "Hello"})
      refute ContentPart.valid?(nil)
    end

    test "valid?/1 validates media types correctly" do
      valid_data = <<137, 80, 78, 71>>
      assert ContentPart.valid?(ContentPart.image_data(valid_data, "image/jpeg"))
      assert ContentPart.valid?(ContentPart.image_data(valid_data, "image/webp"))
      refute ContentPart.valid?(ContentPart.image_data(valid_data, "application/pdf"))
      
      valid_file_data = <<37, 80, 68, 70>>
      assert ContentPart.valid?(ContentPart.file(valid_file_data, "text/plain", "doc.txt"))
      refute ContentPart.valid?(ContentPart.file(valid_file_data, "invalid", "doc.pdf"))
    end

    test "valid?/1 validates tool parts with proper constraints" do
      assert ContentPart.valid?(ContentPart.tool_result("call_123", "tool", "string output"))
      assert ContentPart.valid?(ContentPart.tool_result("call_123", "tool", 42))
      refute ContentPart.valid?(ContentPart.tool_call("", "get_weather", %{}))
      refute ContentPart.valid?(ContentPart.tool_result("call_123", "tool", nil))
    end
  end

  # 1 to_map round-trip test
  test "to_map/1 converts all content part types correctly" do
    # Test representative examples from each type
    assert ContentPart.to_map(ContentPart.text("Hello")) == %{type: "text", text: "Hello"}
    
    assert ContentPart.to_map(ContentPart.image_url("https://example.com/image.png")) == 
           %{type: "image_url", image_url: %{url: "https://example.com/image.png"}}
    
    data = <<137, 80, 78, 71>>
    result = ContentPart.to_map(ContentPart.image_data(data, "image/png"))
    assert %{type: "image_url", image_url: %{url: data_url}} = result
    assert String.starts_with?(data_url, "data:image/png;base64,")
    
    part = ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
    expected = %{
      type: "tool_call",
      id: "call_123", 
      function: %{name: "get_weather", arguments: Jason.encode!(%{location: "NYC"})}
    }
    assert ContentPart.to_map(part) == expected
  end

  # 1 provider_options test
  test "provider_options/1 extracts metadata correctly" do
    assert ContentPart.provider_options(ContentPart.text("Hello")) == %{}
    
    options = %{openai: %{image_detail: "high"}}
    part = ContentPart.text("Hello", metadata: %{provider_options: options})
    assert ContentPart.provider_options(part) == options
    
    part_no_options = ContentPart.text("Hello", metadata: %{other: "data"})
    assert ContentPart.provider_options(part_no_options) == %{}
  end
end
