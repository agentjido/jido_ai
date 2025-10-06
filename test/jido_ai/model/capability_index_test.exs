defmodule Jido.AI.Model.CapabilityIndexTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Model.CapabilityIndex
  alias Jido.AI.Model

  setup do
    # Clear index before each test
    CapabilityIndex.clear()

    # Create sample models for testing
    models = [
      %Model{
        id: "anthropic:claude-3-5-sonnet",
        name: "claude-3-5-sonnet",
        provider: :anthropic,
        capabilities: %{
          tool_call: true,
          reasoning: true,
          temperature: true,
          attachment: false
        }
      },
      %Model{
        id: "openai:gpt-4",
        name: "gpt-4",
        provider: :openai,
        capabilities: %{
          tool_call: true,
          reasoning: false,
          temperature: true,
          attachment: true
        }
      },
      %Model{
        id: "openai:gpt-3.5-turbo",
        name: "gpt-3.5-turbo",
        provider: :openai,
        capabilities: %{
          tool_call: true,
          reasoning: false,
          temperature: true,
          attachment: false
        }
      },
      %Model{
        id: "google:gemini-pro",
        name: "gemini-pro",
        provider: :google,
        capabilities: %{
          tool_call: false,
          reasoning: true,
          temperature: true,
          attachment: true
        }
      },
      %Model{
        id: "ollama:llama2",
        name: "llama2",
        provider: :ollama,
        capabilities: nil
      }
    ]

    {:ok, models: models}
  end

  describe "build/1" do
    test "builds index from models list", %{models: models} do
      assert :ok = CapabilityIndex.build(models)
      assert CapabilityIndex.exists?()
    end

    test "handles models with no capabilities", %{models: models} do
      assert :ok = CapabilityIndex.build(models)
      assert {:ok, %{}} = CapabilityIndex.get_capabilities("ollama:llama2")
    end

    test "creates index tables on first build" do
      refute CapabilityIndex.exists?()
      assert :ok = CapabilityIndex.build([])
      assert CapabilityIndex.exists?()
    end
  end

  describe "lookup_by_capability/2" do
    test "returns models with specific capability", %{models: models} do
      CapabilityIndex.build(models)

      assert {:ok, model_ids} = CapabilityIndex.lookup_by_capability(:tool_call, true)
      assert length(model_ids) == 3
      assert "anthropic:claude-3-5-sonnet" in model_ids
      assert "openai:gpt-4" in model_ids
      assert "openai:gpt-3.5-turbo" in model_ids
    end

    test "returns models with reasoning capability", %{models: models} do
      CapabilityIndex.build(models)

      assert {:ok, model_ids} = CapabilityIndex.lookup_by_capability(:reasoning, true)
      assert length(model_ids) == 2
      assert "anthropic:claude-3-5-sonnet" in model_ids
      assert "google:gemini-pro" in model_ids
    end

    test "returns empty list for capability with no matches", %{models: models} do
      CapabilityIndex.build(models)

      assert {:ok, []} = CapabilityIndex.lookup_by_capability(:unknown_capability, true)
    end

    test "returns error when index not built" do
      assert {:error, :index_not_found} = CapabilityIndex.lookup_by_capability(:tool_call, true)
    end

    test "can lookup by false value", %{models: models} do
      CapabilityIndex.build(models)

      assert {:ok, model_ids} = CapabilityIndex.lookup_by_capability(:attachment, false)
      assert length(model_ids) == 2
      assert "anthropic:claude-3-5-sonnet" in model_ids
      assert "openai:gpt-3.5-turbo" in model_ids
    end
  end

  describe "get_capabilities/1" do
    test "returns capabilities for a model", %{models: models} do
      CapabilityIndex.build(models)

      assert {:ok, capabilities} = CapabilityIndex.get_capabilities("anthropic:claude-3-5-sonnet")
      assert capabilities.tool_call == true
      assert capabilities.reasoning == true
      assert capabilities.temperature == true
      assert capabilities.attachment == false
    end

    test "returns error for non-existent model", %{models: models} do
      CapabilityIndex.build(models)

      assert {:error, :not_found} = CapabilityIndex.get_capabilities("unknown:model")
    end

    test "returns error when index not built" do
      assert {:error, :index_not_found} =
               CapabilityIndex.get_capabilities("anthropic:claude-3-5-sonnet")
    end
  end

  describe "update_model/1" do
    test "updates index when model capabilities change", %{models: models} do
      CapabilityIndex.build(models)

      # Verify initial state
      assert {:ok, ids} = CapabilityIndex.lookup_by_capability(:reasoning, true)
      assert "anthropic:claude-3-5-sonnet" in ids

      # Update model
      updated_model = %Model{
        id: "anthropic:claude-3-5-sonnet",
        name: "claude-3-5-sonnet",
        provider: :anthropic,
        capabilities: %{
          tool_call: true,
          # Changed from true to false
          reasoning: false,
          temperature: true,
          attachment: false
        }
      }

      assert :ok = CapabilityIndex.update_model(updated_model)

      # Verify updated state
      assert {:ok, ids} = CapabilityIndex.lookup_by_capability(:reasoning, true)
      refute "anthropic:claude-3-5-sonnet" in ids

      assert {:ok, ids} = CapabilityIndex.lookup_by_capability(:reasoning, false)
      assert "anthropic:claude-3-5-sonnet" in ids
    end

    test "returns error when index not built" do
      model = %Model{
        id: "test:model",
        name: "test",
        provider: :test,
        capabilities: %{}
      }

      assert {:error, :index_not_found} = CapabilityIndex.update_model(model)
    end
  end

  describe "remove_model/1" do
    test "removes model from index", %{models: models} do
      CapabilityIndex.build(models)

      assert {:ok, ids} = CapabilityIndex.lookup_by_capability(:tool_call, true)
      assert "openai:gpt-4" in ids

      assert :ok = CapabilityIndex.remove_model("openai:gpt-4")

      assert {:ok, ids} = CapabilityIndex.lookup_by_capability(:tool_call, true)
      refute "openai:gpt-4" in ids

      assert {:error, :not_found} = CapabilityIndex.get_capabilities("openai:gpt-4")
    end

    test "handles removing non-existent model", %{models: models} do
      CapabilityIndex.build(models)

      assert :ok = CapabilityIndex.remove_model("unknown:model")
    end
  end

  describe "exists?/0" do
    test "returns false when index not built" do
      refute CapabilityIndex.exists?()
    end

    test "returns true after index is built" do
      CapabilityIndex.build([])
      assert CapabilityIndex.exists?()
    end
  end

  describe "clear/0" do
    test "clears all index data", %{models: models} do
      CapabilityIndex.build(models)

      assert {:ok, ids} = CapabilityIndex.lookup_by_capability(:tool_call, true)
      assert length(ids) > 0

      assert :ok = CapabilityIndex.clear()

      # Index still exists but is empty
      assert CapabilityIndex.exists?()
      assert {:ok, []} = CapabilityIndex.lookup_by_capability(:tool_call, true)
    end

    test "handles clearing when index doesn't exist" do
      refute CapabilityIndex.exists?()
      assert :ok = CapabilityIndex.clear()
    end
  end

  describe "stats/0" do
    test "returns index statistics", %{models: models} do
      CapabilityIndex.build(models)

      assert {:ok, stats} = CapabilityIndex.stats()
      assert is_integer(stats.capability_index_entries)
      assert is_integer(stats.model_entries)
      assert stats.model_entries == 5
      assert is_integer(stats.memory_bytes)
      assert is_float(stats.memory_mb)
    end

    test "returns error when index not built" do
      assert {:error, :index_not_found} = CapabilityIndex.stats()
    end
  end

  describe "performance" do
    test "handles large model sets efficiently" do
      # Create 1000 models
      large_model_set =
        Enum.map(1..1000, fn i ->
          %Model{
            id: "provider#{rem(i, 10)}:model#{i}",
            name: "model#{i}",
            provider: :"provider#{rem(i, 10)}",
            capabilities: %{
              tool_call: rem(i, 2) == 0,
              reasoning: rem(i, 3) == 0,
              temperature: true
            }
          }
        end)

      # Build should complete quickly
      {time_us, :ok} = :timer.tc(fn -> CapabilityIndex.build(large_model_set) end)
      # Less than 500ms
      assert time_us < 500_000

      # Lookups should be fast
      {lookup_time_us, {:ok, _ids}} =
        :timer.tc(fn ->
          CapabilityIndex.lookup_by_capability(:tool_call, true)
        end)

      # Less than 10ms
      assert lookup_time_us < 10_000
    end
  end
end
