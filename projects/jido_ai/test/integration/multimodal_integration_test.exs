defmodule Jido.AI.MultimodalIntegrationTest do
  use ExUnit.Case, async: true

  import Jido.AI.Messages

  alias Jido.AI.Message

  describe "multimodal message validation" do
    test "validates user message with image" do
      message = user_with_image("What's in this image?", "https://example.com/image.jpg")

      assert message.role == :user
      assert Message.valid?(message)
      assert length(message.content) == 2
    end

    test "validates user message with file" do
      message = user_with_file("Analyze this document", "data", "application/pdf", "doc.pdf")

      assert message.role == :user
      assert Message.valid?(message)
      assert length(message.content) == 2
    end
  end
end
