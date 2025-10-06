defmodule Jido.AI.Features.RAGTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Features.RAG
  alias Jido.AI.Model

  describe "supports?/1" do
    test "returns true for Cohere models" do
      model = %Model{provider: :cohere, model: "command-r"}
      assert RAG.supports?(model)
    end

    test "returns true for Google models" do
      model = %Model{provider: :google, model: "gemini-pro"}
      assert RAG.supports?(model)
    end

    test "returns true for Anthropic models" do
      model = %Model{provider: :anthropic, model: "claude-3-sonnet"}
      assert RAG.supports?(model)
    end

    test "returns false for OpenAI models" do
      model = %Model{provider: :openai, model: "gpt-4"}
      refute RAG.supports?(model)
    end
  end

  describe "prepare_documents/2" do
    setup do
      documents = [
        %{content: "First document content", title: "Doc 1", url: "https://example.com/1"},
        %{content: "Second document content", title: "Doc 2"}
      ]

      {:ok, documents: documents}
    end

    test "prepares documents for Cohere", %{documents: documents} do
      {:ok, formatted} = RAG.prepare_documents(documents, :cohere)

      assert length(formatted) == 2
      assert Enum.at(formatted, 0)["text"] == "First document content"
      assert Enum.at(formatted, 0)["title"] == "Doc 1"
      assert Enum.at(formatted, 0)["url"] == "https://example.com/1"
      assert Map.has_key?(Enum.at(formatted, 0), "id")
    end

    test "prepares documents for Google", %{documents: documents} do
      {:ok, formatted} = RAG.prepare_documents(documents, :google)

      assert length(formatted) == 2
      assert get_in(formatted, [Access.at(0), "inline_data", "content"]) == "First document content"
      assert get_in(formatted, [Access.at(0), "inline_data", "mime_type"]) == "text/plain"
    end

    test "prepares documents for Google with metadata" do
      documents = [
        %{content: "Doc with metadata", metadata: %{source: "test", version: 1}}
      ]

      {:ok, formatted} = RAG.prepare_documents(documents, :google)

      # Metadata is preserved with atom keys
      assert get_in(formatted, [Access.at(0), "metadata", :source]) == "test"
      assert get_in(formatted, [Access.at(0), "metadata", :version]) == 1
    end

    test "prepares documents for Anthropic", %{documents: documents} do
      {:ok, formatted_text} = RAG.prepare_documents(documents, :anthropic)

      assert is_binary(formatted_text)
      assert String.contains?(formatted_text, "[1]")
      assert String.contains?(formatted_text, "Doc 1")
      assert String.contains?(formatted_text, "First document content")
      assert String.contains?(formatted_text, "[2]")
    end

    test "returns error for unsupported provider", %{documents: documents} do
      assert {:error, _reason} = RAG.prepare_documents(documents, :openai)
    end

    test "handles documents without optional fields" do
      minimal_docs = [%{content: "Just content"}]

      {:ok, formatted} = RAG.prepare_documents(minimal_docs, :cohere)
      assert Enum.at(formatted, 0)["text"] == "Just content"
      assert Enum.at(formatted, 0)["title"] == "Document"
      assert Map.has_key?(Enum.at(formatted, 0), "id")
    end

    test "returns error for Cohere when document missing content field" do
      invalid_docs = [%{title: "No content"}]

      assert {:error, reason} = RAG.prepare_documents(invalid_docs, :cohere)
      assert reason =~ "missing required :content field"
    end

    test "returns error for Google when document missing content field" do
      invalid_docs = [%{title: "No content"}]

      assert {:error, reason} = RAG.prepare_documents(invalid_docs, :google)
      assert reason =~ "missing required :content field"
    end

    test "returns error for Anthropic when document missing content field" do
      invalid_docs = [%{title: "No content"}]

      assert {:error, reason} = RAG.prepare_documents(invalid_docs, :anthropic)
      assert reason =~ "missing required :content field"
    end

    test "returns error for empty documents list" do
      assert {:error, reason} = RAG.prepare_documents([], :cohere)
      assert reason =~ "cannot be empty"
    end

    test "returns error for too many documents" do
      # Create 101 documents (over the 100 limit)
      too_many_docs = Enum.map(1..101, fn i -> %{content: "Doc #{i}"} end)

      assert {:error, reason} = RAG.prepare_documents(too_many_docs, :cohere)
      assert reason =~ "Too many documents"
      assert reason =~ "100"
    end

    test "returns error for document content too large" do
      # Create a document with content over 500,000 characters
      large_content = String.duplicate("a", 500_001)
      docs = [%{content: large_content}]

      assert {:error, reason} = RAG.prepare_documents(docs, :cohere)
      assert reason =~ "too large"
      assert reason =~ "500000"
    end

    test "returns error for document with empty content" do
      docs = [%{content: ""}]

      assert {:error, reason} = RAG.prepare_documents(docs, :cohere)
      assert reason =~ "cannot be empty"
    end

    test "returns error for document with non-string content" do
      docs = [%{content: 123}]

      assert {:error, reason} = RAG.prepare_documents(docs, :cohere)
      assert reason =~ "must be a string"
    end

    test "returns error for non-map document" do
      docs = ["invalid document"]

      assert {:error, reason} = RAG.prepare_documents(docs, :cohere)
      assert reason =~ "must be a map"
    end

    test "returns error for non-list documents parameter" do
      assert {:error, reason} = RAG.prepare_documents(%{not: "a list"}, :cohere)
      assert reason =~ "must be a list"
    end
  end

  describe "extract_citations/2" do
    test "extracts citations from Cohere response" do
      response = %{
        "citations" => [
          %{
            "text" => "cited text",
            "document_ids" => ["0"],
            "start" => 10,
            "end" => 20
          }
        ]
      }

      {:ok, citations} = RAG.extract_citations(response, :cohere)

      assert length(citations) == 1
      assert Enum.at(citations, 0).text == "cited text"
      assert Enum.at(citations, 0).document_index == 0
      assert Enum.at(citations, 0).start == 10
      assert Enum.at(citations, 0).end == 20
    end

    test "extracts citations from Google response" do
      response = %{
        "grounding_metadata" => %{
          "grounding_chunks" => [
            %{"text" => "chunk 1"},
            %{"text" => "chunk 2"}
          ]
        }
      }

      {:ok, citations} = RAG.extract_citations(response, :google)

      assert length(citations) == 2
      assert Enum.at(citations, 0).text == "chunk 1"
    end

    test "returns empty list for Anthropic" do
      response = %{"content" => "response text"}

      {:ok, citations} = RAG.extract_citations(response, :anthropic)

      assert citations == []
    end

    test "returns empty list for response without citations" do
      response = %{}

      {:ok, citations} = RAG.extract_citations(response, :cohere)

      assert citations == []
    end

    test "handles Cohere citations with integer document_ids" do
      response = %{
        "citations" => [
          %{
            "text" => "cited",
            "document_ids" => [2],
            "start" => 0,
            "end" => 5
          }
        ]
      }

      {:ok, citations} = RAG.extract_citations(response, :cohere)

      assert Enum.at(citations, 0).document_index == 2
    end

    test "handles Cohere citations with string document_ids" do
      response = %{
        "citations" => [
          %{
            "text" => "cited",
            "document_ids" => ["3"],
            "start" => 0,
            "end" => 5
          }
        ]
      }

      {:ok, citations} = RAG.extract_citations(response, :cohere)

      assert Enum.at(citations, 0).document_index == 3
    end

    test "handles Cohere citations with invalid document_ids" do
      response = %{
        "citations" => [
          %{
            "text" => "cited",
            "document_ids" => ["invalid"],
            "start" => 0,
            "end" => 5
          }
        ]
      }

      {:ok, citations} = RAG.extract_citations(response, :cohere)

      assert Enum.at(citations, 0).document_index == 0
    end

    test "returns empty list for unsupported provider" do
      response = %{"content" => "Response"}

      {:ok, citations} = RAG.extract_citations(response, :ollama)

      assert citations == []
    end
  end

  describe "build_rag_options/3" do
    setup do
      documents = [
        %{content: "Document 1"},
        %{content: "Document 2"}
      ]

      base_opts = %{temperature: 0.7, max_tokens: 500}

      {:ok, documents: documents, base_opts: base_opts}
    end

    test "builds options for Cohere", %{documents: documents, base_opts: base_opts} do
      {:ok, opts} = RAG.build_rag_options(documents, base_opts, :cohere)

      assert opts.temperature == 0.7
      assert opts.max_tokens == 500
      assert Map.has_key?(opts, :documents)
      assert is_list(opts.documents)
      assert length(opts.documents) == 2
    end

    test "builds options for Google", %{documents: documents, base_opts: base_opts} do
      {:ok, opts} = RAG.build_rag_options(documents, base_opts, :google)

      assert opts.temperature == 0.7
      assert Map.has_key?(opts, :tools)
      assert is_list(opts.tools)
    end

    test "builds options for Anthropic", %{documents: documents, base_opts: base_opts} do
      {:ok, opts} = RAG.build_rag_options(documents, base_opts, :anthropic)

      assert opts.temperature == 0.7
      assert Map.has_key?(opts, :system)
      assert String.contains?(opts.system, "Reference Documents:")
      assert String.contains?(opts.system, "[1]")
    end

    test "preserves existing system prompt for Anthropic", %{documents: documents} do
      base_opts = %{system: "You are helpful", temperature: 0.7}

      {:ok, opts} = RAG.build_rag_options(documents, base_opts, :anthropic)

      assert String.contains?(opts.system, "You are helpful")
      assert String.contains?(opts.system, "Reference Documents:")
    end

    test "returns error for unsupported provider", %{documents: documents, base_opts: base_opts} do
      assert {:error, _reason} = RAG.build_rag_options(documents, base_opts, :openai)
    end
  end
end
