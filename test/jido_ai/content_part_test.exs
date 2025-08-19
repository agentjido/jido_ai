defmodule Jido.AI.ContentPartTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ContentPart

  describe "ContentPart creation" do
    test "creates valid image_url content part" do
      url = "https://example.com/image.jpg"
      content_part = ContentPart.image_url(url)

      assert content_part.type == :image_url
      assert content_part.url == url
      assert ContentPart.valid?(content_part)
    end

    test "creates valid image_data content part" do
      data = "base64data"
      media_type = "image/jpeg"
      content_part = ContentPart.image_data(data, media_type)

      assert content_part.type == :image
      assert content_part.data == data
      assert content_part.media_type == media_type
      assert ContentPart.valid?(content_part)
    end

    test "creates valid file content part" do
      data = "file content"
      media_type = "application/pdf"
      filename = "document.pdf"
      content_part = ContentPart.file(data, media_type, filename)

      assert content_part.type == :file
      assert content_part.data == data
      assert content_part.media_type == media_type
      assert content_part.filename == filename
      assert ContentPart.valid?(content_part)
    end
  end

  describe "ContentPart.to_map/1" do
    test "converts content parts to provider format" do
      # Image URL
      image_url_part = ContentPart.image_url("https://example.com/image.jpg")
      image_url_map = ContentPart.to_map(image_url_part)
      assert %{type: "image_url", image_url: %{url: "https://example.com/image.jpg"}} = image_url_map

      # Image data converts to data URL
      image_data_part = ContentPart.image_data("data", "image/jpeg")
      image_data_map = ContentPart.to_map(image_data_part)
      expected_url = "data:image/jpeg;base64," <> Base.encode64("data")
      assert %{type: "image_url", image_url: %{url: ^expected_url}} = image_data_map

      # File data gets base64 encoded
      file_part = ContentPart.file("data", "application/pdf", "doc.pdf")
      file_map = ContentPart.to_map(file_part)
      expected_data = Base.encode64("data")

      assert %{type: "file", file: %{data: ^expected_data, media_type: "application/pdf", filename: "doc.pdf"}} =
               file_map
    end
  end
end
