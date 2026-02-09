defmodule JidoAITest.Actions.RLM.SubqueryBatchTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.RLM.LLM.SubqueryBatch
  alias Jido.AI.RLM.{ContextStore, WorkspaceStore}

  setup do
    context_data = "Hello World. This is chunk zero. More data here for chunk one."
    {:ok, context_ref} = ContextStore.put(context_data, "test-#{System.unique_integer()}")

    chunk_index = %{
      "c_0" => %{byte_start: 0, byte_end: 30},
      "c_1" => %{byte_start: 31, byte_end: 61}
    }

    {:ok, workspace_ref} =
      WorkspaceStore.init("test-#{System.unique_integer()}", %{
        chunks: %{index: chunk_index}
      })

    %{
      context_ref: context_ref,
      workspace_ref: workspace_ref,
      chunk_index: chunk_index
    }
  end

  describe "fetch_chunk_text/4" do
    test "fetches text for a known chunk", ctx do
      workspace = WorkspaceStore.get(ctx.workspace_ref)

      text =
        SubqueryBatch.fetch_chunk_text("c_0", workspace, ctx.context_ref, 50_000)

      assert text == "Hello World. This is chunk zer"
    end

    test "returns empty string for unknown chunk_id", ctx do
      workspace = WorkspaceStore.get(ctx.workspace_ref)

      text =
        SubqueryBatch.fetch_chunk_text("c_999", workspace, ctx.context_ref, 50_000)

      assert text == ""
    end

    test "respects max_bytes limit", ctx do
      workspace = WorkspaceStore.get(ctx.workspace_ref)

      text = SubqueryBatch.fetch_chunk_text("c_0", workspace, ctx.context_ref, 10)

      assert byte_size(text) == 10
      assert text == "Hello Worl"
    end

    test "handles workspace without chunks key", ctx do
      {:ok, empty_ref} = WorkspaceStore.init("empty-#{System.unique_integer()}", %{})
      workspace = WorkspaceStore.get(empty_ref)

      text = SubqueryBatch.fetch_chunk_text("c_0", workspace, ctx.context_ref, 50_000)

      assert text == ""
    end
  end

  describe "schema validation" do
    test "accepts valid params" do
      params = %{
        chunk_ids: ["c_0", "c_1"],
        prompt: "Summarize this section",
        max_concurrency: 5,
        timeout: 30_000,
        max_chunk_bytes: 25_000
      }

      schema = SubqueryBatch.__action_metadata__().schema
      assert {:ok, _validated} = Zoi.parse(schema, params)
    end

    test "accepts params with optional model" do
      params = %{
        chunk_ids: ["c_0"],
        prompt: "Analyze this",
        model: "anthropic:claude-haiku-4-5"
      }

      schema = SubqueryBatch.__action_metadata__().schema
      assert {:ok, validated} = Zoi.parse(schema, params)
      assert validated.model == "anthropic:claude-haiku-4-5"
    end

    test "applies defaults for optional fields" do
      params = %{
        chunk_ids: ["c_0"],
        prompt: "Analyze"
      }

      schema = SubqueryBatch.__action_metadata__().schema
      assert {:ok, validated} = Zoi.parse(schema, params)
      assert validated.max_concurrency == 10
      assert validated.timeout == 60_000
      assert validated.max_chunk_bytes == 50_000
    end

    test "rejects missing required fields" do
      schema = SubqueryBatch.__action_metadata__().schema
      assert {:error, _} = Zoi.parse(schema, %{})
    end
  end
end
