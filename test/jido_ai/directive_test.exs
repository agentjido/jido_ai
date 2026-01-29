defmodule Jido.AI.DirectiveTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Directive.{ReqLLMEmbed, ReqLLMGenerate, ReqLLMStream, ToolExec}
  alias Jido.AI.Signal.EmbedResult

  describe "ReqLLMStream" do
    test "creates directive with required fields" do
      directive =
        ReqLLMStream.new!(%{
          id: "call_123",
          model: "anthropic:claude-haiku-4-5",
          context: [%{role: :user, content: "Hello"}]
        })

      assert directive.id == "call_123"
      assert directive.model == "anthropic:claude-haiku-4-5"
      assert directive.context == [%{role: :user, content: "Hello"}]
      assert directive.tools == []
      assert directive.tool_choice == :auto
      assert directive.max_tokens == 1024
      assert directive.temperature == 0.2
    end

    test "creates directive with model_alias" do
      directive =
        ReqLLMStream.new!(%{
          id: "call_456",
          model_alias: :fast,
          context: [%{role: :user, content: "Test"}]
        })

      assert directive.model_alias == :fast
      assert is_nil(directive.model)
    end

    test "creates directive with system_prompt" do
      directive =
        ReqLLMStream.new!(%{
          id: "call_789",
          model: "anthropic:claude-haiku-4-5",
          system_prompt: "You are a helpful assistant.",
          context: [%{role: :user, content: "Hello"}]
        })

      assert directive.system_prompt == "You are a helpful assistant."
    end

    test "creates directive with timeout" do
      directive =
        ReqLLMStream.new!(%{
          id: "call_abc",
          model: "anthropic:claude-haiku-4-5",
          timeout: 30_000,
          context: [%{role: :user, content: "Hello"}]
        })

      assert directive.timeout == 30_000
    end

    test "creates directive with all optional fields" do
      directive =
        ReqLLMStream.new!(%{
          id: "call_full",
          model: "anthropic:claude-haiku-4-5",
          model_alias: :capable,
          system_prompt: "Be concise.",
          context: [%{role: :user, content: "Hello"}],
          tools: [],
          tool_choice: :none,
          max_tokens: 2048,
          temperature: 0.5,
          timeout: 60_000,
          metadata: %{request_id: "req_123"}
        })

      assert directive.id == "call_full"
      assert directive.model == "anthropic:claude-haiku-4-5"
      assert directive.model_alias == :capable
      assert directive.system_prompt == "Be concise."
      assert directive.tool_choice == :none
      assert directive.max_tokens == 2048
      assert directive.temperature == 0.5
      assert directive.timeout == 60_000
      assert directive.metadata == %{request_id: "req_123"}
    end

    test "raises on missing required fields" do
      assert_raise RuntimeError, ~r/Invalid ReqLLMStream/, fn ->
        ReqLLMStream.new!(%{model: "anthropic:claude-haiku-4-5"})
      end
    end
  end

  describe "ReqLLMGenerate" do
    test "creates non-streaming directive with required fields" do
      directive =
        ReqLLMGenerate.new!(%{
          id: "gen_123",
          model: "anthropic:claude-haiku-4-5",
          context: [%{role: :user, content: "Hello"}]
        })

      assert directive.id == "gen_123"
      assert directive.model == "anthropic:claude-haiku-4-5"
      assert directive.context == [%{role: :user, content: "Hello"}]
      assert directive.tools == []
      assert directive.tool_choice == :auto
      assert directive.max_tokens == 1024
      assert directive.temperature == 0.2
    end

    test "creates directive with model_alias" do
      directive =
        ReqLLMGenerate.new!(%{
          id: "gen_456",
          model_alias: :reasoning,
          context: [%{role: :user, content: "Solve this problem"}]
        })

      assert directive.model_alias == :reasoning
      assert is_nil(directive.model)
    end

    test "creates directive with system_prompt and timeout" do
      directive =
        ReqLLMGenerate.new!(%{
          id: "gen_789",
          model: "openai:gpt-4o",
          system_prompt: "You are an expert.",
          timeout: 45_000,
          context: [%{role: :user, content: "Explain quantum computing"}]
        })

      assert directive.system_prompt == "You are an expert."
      assert directive.timeout == 45_000
    end

    test "raises on missing required fields" do
      assert_raise RuntimeError, ~r/Invalid ReqLLMGenerate/, fn ->
        ReqLLMGenerate.new!(%{model: "anthropic:claude-haiku-4-5"})
      end
    end
  end

  describe "ReqLLMEmbed" do
    test "creates embedding directive with single text" do
      directive =
        ReqLLMEmbed.new!(%{
          id: "embed_123",
          model: "openai:text-embedding-3-small",
          texts: "Hello, world!"
        })

      assert directive.id == "embed_123"
      assert directive.model == "openai:text-embedding-3-small"
      assert directive.texts == "Hello, world!"
      assert is_nil(directive.dimensions)
      assert is_nil(directive.timeout)
    end

    test "creates embedding directive with batch texts" do
      texts = ["Hello", "World", "Test"]

      directive =
        ReqLLMEmbed.new!(%{
          id: "embed_batch",
          model: "openai:text-embedding-3-small",
          texts: texts
        })

      assert directive.texts == texts
    end

    test "creates embedding directive with dimensions" do
      directive =
        ReqLLMEmbed.new!(%{
          id: "embed_dims",
          model: "openai:text-embedding-3-small",
          texts: "Test text",
          dimensions: 256
        })

      assert directive.dimensions == 256
    end

    test "creates embedding directive with timeout" do
      directive =
        ReqLLMEmbed.new!(%{
          id: "embed_timeout",
          model: "openai:text-embedding-3-small",
          texts: "Test text",
          timeout: 10_000
        })

      assert directive.timeout == 10_000
    end

    test "creates embedding directive with metadata" do
      directive =
        ReqLLMEmbed.new!(%{
          id: "embed_meta",
          model: "openai:text-embedding-3-small",
          texts: "Test",
          metadata: %{source: "document.pdf", page: 1}
        })

      assert directive.metadata == %{source: "document.pdf", page: 1}
    end

    test "raises on missing required fields" do
      assert_raise RuntimeError, ~r/Invalid ReqLLMEmbed/, fn ->
        ReqLLMEmbed.new!(%{id: "embed_123"})
      end
    end
  end

  describe "ToolExec" do
    test "creates directive with required fields" do
      directive =
        ToolExec.new!(%{
          id: "call_123",
          tool_name: "calculator"
        })

      assert directive.id == "call_123"
      assert directive.tool_name == "calculator"
      assert directive.arguments == %{}
      assert directive.context == %{}
      assert directive.metadata == %{}
    end

    test "creates directive with arguments" do
      directive =
        ToolExec.new!(%{
          id: "call_456",
          tool_name: "calculator",
          arguments: %{"a" => 1, "b" => 2, "operation" => "add"}
        })

      assert directive.arguments == %{"a" => 1, "b" => 2, "operation" => "add"}
    end

    test "creates directive with context" do
      directive =
        ToolExec.new!(%{
          id: "call_789",
          tool_name: "weather",
          context: %{user_id: "user_123", session_id: "sess_456"}
        })

      assert directive.context == %{user_id: "user_123", session_id: "sess_456"}
    end

    test "creates directive with metadata" do
      directive =
        ToolExec.new!(%{
          id: "call_abc",
          tool_name: "search",
          metadata: %{request_id: "req_123", timestamp: ~U[2026-01-03 12:00:00Z]}
        })

      assert directive.metadata == %{request_id: "req_123", timestamp: ~U[2026-01-03 12:00:00Z]}
    end

    test "creates directive with all optional fields" do
      directive =
        ToolExec.new!(%{
          id: "call_full",
          tool_name: "database",
          arguments: %{query: "SELECT * FROM users"},
          context: %{db_pool: :primary},
          metadata: %{traced: true}
        })

      assert directive.id == "call_full"
      assert directive.tool_name == "database"
      assert directive.arguments == %{query: "SELECT * FROM users"}
      assert directive.context == %{db_pool: :primary}
      assert directive.metadata == %{traced: true}
    end

    test "raises on missing required fields - id" do
      assert_raise RuntimeError, ~r/Invalid ToolExec/, fn ->
        ToolExec.new!(%{
          tool_name: "calculator"
        })
      end
    end

    test "raises on missing required fields - tool_name" do
      assert_raise RuntimeError, ~r/Invalid ToolExec/, fn ->
        ToolExec.new!(%{
          id: "call_123"
        })
      end
    end
  end

  describe "EmbedResult signal" do
    test "creates embed result signal with successful result" do
      embeddings = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]
      result = {:ok, %{embeddings: embeddings, count: 2}}

      signal =
        EmbedResult.new!(%{
          call_id: "embed_123",
          result: result
        })

      assert signal.data.call_id == "embed_123"
      assert signal.data.result == result
      assert signal.type == "ai.embed_result"
    end

    test "creates embed result signal with error result" do
      result = {:error, %{reason: "Rate limit exceeded"}}

      signal =
        EmbedResult.new!(%{
          call_id: "embed_456",
          result: result
        })

      assert signal.data.call_id == "embed_456"
      assert signal.data.result == result
    end

    test "creates embed result signal with single embedding" do
      embedding = [0.1, 0.2, 0.3, 0.4, 0.5]
      result = {:ok, %{embeddings: embedding, count: 1}}

      signal =
        EmbedResult.new!(%{
          call_id: "embed_single",
          result: result
        })

      assert signal.data.result == result
    end
  end

  describe "ToolExec DirectiveExec" do
    alias Jido.AI.Tools.Registry

    # Define test Action module
    defmodule TestActions.Calculator do
      use Jido.Action,
        name: "calculator",
        description: "Performs arithmetic calculations",
        schema: [
          a: [type: :integer, required: true, doc: "First operand"],
          b: [type: :integer, required: true, doc: "Second operand"]
        ]

      @impl true
      def run(params, _context) do
        {:ok, %{result: params.a + params.b}}
      end
    end

    # Additional test Action module
    defmodule TestActions.Echo do
      use Jido.Action,
        name: "echo",
        description: "Echoes back the input message",
        schema: [
          message: [type: :string, required: true, doc: "Message to echo"]
        ]

      @impl true
      def run(params, _context) do
        {:ok, %{echoed: params.message}}
      end
    end

    setup do
      # Ensure registry is started and clear before each test
      Registry.ensure_started()
      Registry.clear()
      :ok
    end

    test "ToolExec creates valid directive for Registry lookup" do
      directive =
        ToolExec.new!(%{
          id: "call_456",
          tool_name: "calculator",
          arguments: %{"a" => "10", "b" => "20"}
        })

      assert directive.id == "call_456"
      assert directive.tool_name == "calculator"
      assert directive.arguments == %{"a" => "10", "b" => "20"}
    end

    test "ToolExec with context passes context to execution" do
      directive =
        ToolExec.new!(%{
          id: "call_789",
          tool_name: "echo",
          arguments: %{"message" => "hello"},
          context: %{user_id: "user_123"}
        })

      assert directive.context == %{user_id: "user_123"}
    end

    test "ToolExec with metadata preserves metadata" do
      directive =
        ToolExec.new!(%{
          id: "call_meta",
          tool_name: "test_tool",
          arguments: %{},
          metadata: %{trace_id: "abc123", parent_span: "xyz"}
        })

      assert directive.metadata == %{trace_id: "abc123", parent_span: "xyz"}
    end
  end
end
