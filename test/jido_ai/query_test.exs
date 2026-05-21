defmodule Jido.AI.QueryTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Query
  alias ReqLLM.Message.ContentPart

  describe "content_part?/1" do
    test "accepts compatible file and video content maps" do
      assert Query.content_part?(%{type: :file, file_id: "file_123"})
      assert Query.content_part?(%{type: "file", file_id: "file_123"})
      assert Query.content_part?(%{"type" => "file", "file_id" => "file_123"})
      assert Query.content_part?(%{type: :video_url, url: "https://example.com/video.mp4"})
      assert Query.content_part?(%{"type" => "video_url", "url" => "https://example.com/video.mp4"})
      assert Query.content_part?(%{type: :document, source: %{file_id: "file_123"}})
      assert Query.content_part?(%{"type" => "file_id", "file_id" => "file_123"})
    end
  end

  describe "attach_file_references/2" do
    test "returns the original query when no file reference options are provided" do
      assert {:ok, "Summarize this."} = Query.attach_file_references("Summarize this.", [])
    end

    test "validates missing file ids before checking ReqLLM support" do
      assert {:error, {:invalid_file_reference, :missing_file_id}} =
               Query.attach_file_references("Summarize this.", file_id: " ")
    end

    test "returns a structured error for malformed list-shaped references" do
      assert {:error, {:invalid_file_reference, :missing_file_id}} =
               Query.attach_file_references("Summarize this.", file_id: ["file_123"])
    end

    test "treats a keyword file reference as a single reference" do
      result =
        Query.attach_file_references("Summarize this.",
          file_references: [
            file_id: "file_123",
            media_type: "application/pdf",
            title: "Quarterly report"
          ]
        )

      if file_reference_supported?() do
        assert {:ok, [text_part, file_part]} = result
        assert %ContentPart{type: :text, text: "Summarize this."} = text_part

        file_part = Map.from_struct(file_part)
        assert file_part.type == :file
        assert file_part.file_id == "file_123"
        assert file_part.media_type == "application/pdf"
        assert file_part.metadata.title == "Quarterly report"
      else
        assert {:error, {:unsupported_content_part_file_id, message}} = result
        assert message =~ "ReqLLM.Message.ContentPart.file_id/3"
      end
    end

    test "accepts singular file_reference and normalizes optional metadata" do
      result =
        Query.attach_file_references("Summarize this.",
          file_reference: [
            file_id: "file_123",
            media_type: " ",
            filename: " report.pdf ",
            metadata: [custom: true],
            context: "Uploaded through the Files API"
          ]
        )

      if file_reference_supported?() do
        assert {:ok, [_text_part, file_part]} = result

        file_part = Map.from_struct(file_part)
        assert file_part.media_type == "application/pdf"
        assert file_part.filename == "report.pdf"
        assert file_part.metadata == %{custom: true, context: "Uploaded through the Files API"}
      else
        assert {:error, {:unsupported_content_part_file_id, message}} = result
        assert message =~ "ReqLLM.Message.ContentPart.file_id/3"
      end
    end

    test "accepts nested source options as keyword lists" do
      result =
        Query.attach_file_references("Summarize this.",
          file_reference: [
            source: [
              file_id: " file_123 ",
              media_type: " application/pdf "
            ],
            filename: " report.pdf "
          ]
        )

      if file_reference_supported?() do
        assert {:ok, [_text_part, file_part]} = result

        file_part = Map.from_struct(file_part)
        assert file_part.file_id == "file_123"
        assert file_part.media_type == "application/pdf"
        assert file_part.filename == "report.pdf"
      else
        assert {:error, {:unsupported_content_part_file_id, message}} = result
        assert message =~ "ReqLLM.Message.ContentPart.file_id/3"
      end
    end

    test "appends normalized file reference content parts when ReqLLM supports them" do
      result =
        Query.attach_file_references("Compare these files.",
          file_id: "file_document",
          file_references: [
            %{
              "source" => %{"file_id" => "file_image", "media_type" => "image/png"},
              "filename" => "chart.png",
              "metadata" => %{"custom" => true}
            }
          ]
        )

      if file_reference_supported?() do
        assert {:ok, [text_part, document_part, image_part]} = result
        assert %ContentPart{type: :text, text: "Compare these files."} = text_part

        document_part = Map.from_struct(document_part)
        assert document_part.type == :file
        assert document_part.file_id == "file_document"
        assert document_part.media_type == "application/pdf"

        image_part = Map.from_struct(image_part)
        assert image_part.type == :file
        assert image_part.file_id == "file_image"
        assert image_part.media_type == "image/png"
        assert image_part.filename == "chart.png"
        assert image_part.metadata == %{"custom" => true}
      else
        assert {:error, {:unsupported_content_part_file_id, message}} = result
        assert message =~ "ReqLLM.Message.ContentPart.file_id/3"
      end
    end
  end

  describe "summarize/1" do
    test "renders file content parts without exposing raw payloads" do
      summary =
        Query.summarize([
          ContentPart.text("Review this file."),
          ContentPart.file("PDF", "report.pdf", "application/pdf"),
          %{"type" => "file", "filename" => "appendix.pdf"},
          %{"type" => "document", "filename" => "source.pdf"},
          %{type: :file_id},
          %{type: "file", filename: "notes.txt"}
        ])

      assert summary ==
               "Review this file.\n[File: report.pdf]\n[File: appendix.pdf]\n[File: source.pdf]\n[File]\n[File: notes.txt]"
    end
  end

  defp file_reference_supported? do
    function_exported?(ContentPart, :file_id, 3)
  end
end
