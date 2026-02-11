defmodule JidoAITest.Actions.RLM.AgentSpawnTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.RLM.Agent.Spawn
  alias Jido.AI.RLM.{ChunkProjection, ContextStore, WorkspaceStore}

  setup do
    context_data = "Hello World. This is chunk zero. More data here for chunk one."
    {:ok, context_ref} = ContextStore.put(context_data, "test-#{System.unique_integer()}")
    {:ok, workspace_ref} = WorkspaceStore.init("test-#{System.unique_integer()}")

    {:ok, projection, _chunks} =
      ChunkProjection.create(workspace_ref, context_ref, %{strategy: "bytes", size: 30, overlap: 0, max_chunks: 2}, %{})

    chunk_index = projection.index

    %{
      context_ref: context_ref,
      workspace_ref: workspace_ref,
      chunk_index: chunk_index,
      projection: projection
    }
  end

  describe "schema validation" do
    test "accepts valid params with chunk_ids and query" do
      params = %{
        chunk_ids: ["c_0", "c_1"],
        query: "Summarize this section"
      }

      schema = Spawn.__action_metadata__().schema
      assert {:ok, _validated} = Zoi.parse(schema, params)
    end

    test "applies defaults for optional fields" do
      params = %{
        chunk_ids: ["c_0"],
        query: "Analyze"
      }

      schema = Spawn.__action_metadata__().schema
      assert {:ok, validated} = Zoi.parse(schema, params)
      assert validated.max_iterations == 8
      assert validated.timeout == 120_000
      assert validated.max_concurrency == 5
      assert validated.max_chunk_bytes == 100_000
    end

    test "accepts params with optional model" do
      params = %{
        chunk_ids: ["c_0"],
        query: "Analyze this",
        model: "anthropic:claude-haiku-4-5"
      }

      schema = Spawn.__action_metadata__().schema
      assert {:ok, validated} = Zoi.parse(schema, params)
      assert validated.model == "anthropic:claude-haiku-4-5"
    end

    test "rejects missing required fields" do
      schema = Spawn.__action_metadata__().schema
      assert {:error, _} = Zoi.parse(schema, %{})
    end
  end

  describe "fetch_chunk_text/4" do
    test "fetches text for a known chunk", ctx do
      text =
        Spawn.fetch_chunk_text("c_0", ctx.projection, ctx.context_ref, 50_000)

      assert text == "Hello World. This is chunk zer"
    end

    test "returns empty string for unknown chunk_id", ctx do
      text =
        Spawn.fetch_chunk_text("c_999", ctx.projection, ctx.context_ref, 50_000)

      assert text == ""
    end

    test "respects max_bytes limit", ctx do
      text = Spawn.fetch_chunk_text("c_0", ctx.projection, ctx.context_ref, 10)

      assert byte_size(text) == 10
      assert text == "Hello Worl"
    end

    test "handles workspace without chunks key", ctx do
      empty_projection = %{ctx.projection | index: %{}}
      text = Spawn.fetch_chunk_text("c_0", empty_projection, ctx.context_ref, 50_000)

      assert text == ""
    end
  end

  describe "depth degradation logic" do
    test "module compiles and defines run/2" do
      assert function_exported?(Spawn, :run, 2)
    end

    test "schema validates params that would trigger depth-limited path" do
      params = %{
        chunk_ids: ["c_0"],
        query: "Deep analysis needed",
        max_iterations: 4,
        timeout: 60_000,
        max_concurrency: 2,
        max_chunk_bytes: 50_000
      }

      schema = Spawn.__action_metadata__().schema
      assert {:ok, validated} = Zoi.parse(schema, params)
      assert validated.max_iterations == 4
      assert validated.max_concurrency == 2
    end
  end
end
