defmodule Jido.AI.Test.Fixtures.ContentFixtures do
  @moduledoc """
  Shared fixtures for ContentPart testing
  """
  alias Jido.AI.ContentPart

  def image_url(url \\ "https://example.com/image.jpg", opts \\ []) do
    ContentPart.image_url(url, opts)
  end

  def image_data(data \\ "base64data", media_type \\ "image/jpeg") do
    ContentPart.image_data(data, media_type)
  end

  def pdf_data(data \\ "pdf content", filename \\ "document.pdf") do
    ContentPart.file(data, "application/pdf", filename)
  end

  def text_content(text \\ "Hello world") do
    ContentPart.text(text)
  end
end
