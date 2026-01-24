defmodule Jido.AI.GEPA.PromptVariantTest do
  use ExUnit.Case, async: true

  alias Jido.AI.GEPA.PromptVariant

  # ============================================================================
  # Struct Creation - new/1
  # ============================================================================

  describe "new/1" do
    test "creates variant with string template" do
      assert {:ok, variant} = PromptVariant.new(%{template: "Be helpful"})

      assert variant.template == "Be helpful"
      assert variant.generation == 0
      assert variant.parents == []
      assert variant.accuracy == nil
      assert variant.token_cost == nil
      assert variant.metadata == %{}
      assert String.starts_with?(variant.id, "pv_")
    end

    test "creates variant with map template" do
      template = %{system: "You are helpful", user: "{{input}}"}
      assert {:ok, variant} = PromptVariant.new(%{template: template})

      assert variant.template == template
    end

    test "uses provided id" do
      assert {:ok, variant} = PromptVariant.new(%{template: "test", id: "my-custom-id"})
      assert variant.id == "my-custom-id"
    end

    test "uses provided generation" do
      assert {:ok, variant} = PromptVariant.new(%{template: "test", generation: 5})
      assert variant.generation == 5
    end

    test "uses provided parents" do
      parents = ["parent1", "parent2"]
      assert {:ok, variant} = PromptVariant.new(%{template: "test", parents: parents})
      assert variant.parents == parents
    end

    test "uses provided metadata" do
      metadata = %{source: "mutation", notes: "improved clarity"}
      assert {:ok, variant} = PromptVariant.new(%{template: "test", metadata: metadata})
      assert variant.metadata == metadata
    end

    test "returns error when template is missing" do
      assert {:error, :template_required} = PromptVariant.new(%{})
    end

    test "returns error when template is empty string" do
      assert {:error, :invalid_template} = PromptVariant.new(%{template: ""})
    end

    test "returns error when template is empty map" do
      assert {:error, :invalid_template} = PromptVariant.new(%{template: %{}})
    end

    test "returns error when attrs is not a map" do
      assert {:error, :invalid_attrs} = PromptVariant.new("not a map")
      assert {:error, :invalid_attrs} = PromptVariant.new(nil)
    end
  end

  # ============================================================================
  # Struct Creation - new!/1
  # ============================================================================

  describe "new!/1" do
    test "creates variant on success" do
      variant = PromptVariant.new!(%{template: "Be helpful"})
      assert variant.template == "Be helpful"
    end

    test "raises ArgumentError on missing template" do
      assert_raise ArgumentError, "template is required", fn ->
        PromptVariant.new!(%{})
      end
    end

    test "raises ArgumentError on invalid template" do
      assert_raise ArgumentError, "template must be a non-empty string or map", fn ->
        PromptVariant.new!(%{template: ""})
      end
    end
  end

  # ============================================================================
  # Metric Updates
  # ============================================================================

  describe "update_metrics/2" do
    test "updates accuracy and token_cost" do
      variant = PromptVariant.new!(%{template: "test"})

      updated =
        PromptVariant.update_metrics(variant, %{
          accuracy: 0.85,
          token_cost: 1500
        })

      assert updated.accuracy == 0.85
      assert updated.token_cost == 1500
      assert updated.latency_ms == nil
    end

    test "updates all metrics including latency" do
      variant = PromptVariant.new!(%{template: "test"})

      updated =
        PromptVariant.update_metrics(variant, %{
          accuracy: 0.9,
          token_cost: 2000,
          latency_ms: 250
        })

      assert updated.accuracy == 0.9
      assert updated.token_cost == 2000
      assert updated.latency_ms == 250
    end

    test "clamps accuracy to 0.0-1.0 range" do
      variant = PromptVariant.new!(%{template: "test"})

      updated = PromptVariant.update_metrics(variant, %{accuracy: 1.5, token_cost: 100})
      assert updated.accuracy == 1.0

      updated = PromptVariant.update_metrics(variant, %{accuracy: -0.5, token_cost: 100})
      assert updated.accuracy == 0.0
    end

    test "rounds float token_cost to integer" do
      variant = PromptVariant.new!(%{template: "test"})

      updated = PromptVariant.update_metrics(variant, %{accuracy: 0.5, token_cost: 100.7})
      assert updated.token_cost == 101
    end

    test "handles negative token_cost by setting to 0" do
      variant = PromptVariant.new!(%{template: "test"})

      updated = PromptVariant.update_metrics(variant, %{accuracy: 0.5, token_cost: -100})
      assert updated.token_cost == 0
    end

    test "preserves other fields when updating metrics" do
      variant =
        PromptVariant.new!(%{
          template: "test",
          generation: 3,
          parents: ["p1"],
          metadata: %{tag: "v1"}
        })

      updated = PromptVariant.update_metrics(variant, %{accuracy: 0.9, token_cost: 100})

      assert updated.template == "test"
      assert updated.generation == 3
      assert updated.parents == ["p1"]
      assert updated.metadata == %{tag: "v1"}
    end
  end

  # ============================================================================
  # Evaluated Check
  # ============================================================================

  describe "evaluated?/1" do
    test "returns false for unevaluated variant" do
      variant = PromptVariant.new!(%{template: "test"})
      refute PromptVariant.evaluated?(variant)
    end

    test "returns false when only accuracy is set" do
      variant = PromptVariant.new!(%{template: "test"})
      variant = %{variant | accuracy: 0.9}
      refute PromptVariant.evaluated?(variant)
    end

    test "returns false when only token_cost is set" do
      variant = PromptVariant.new!(%{template: "test"})
      variant = %{variant | token_cost: 100}
      refute PromptVariant.evaluated?(variant)
    end

    test "returns true when both accuracy and token_cost are set" do
      variant = PromptVariant.new!(%{template: "test"})
      variant = PromptVariant.update_metrics(variant, %{accuracy: 0.9, token_cost: 100})
      assert PromptVariant.evaluated?(variant)
    end
  end

  # ============================================================================
  # Child Creation
  # ============================================================================

  describe "create_child/2" do
    test "creates child with incremented generation" do
      parent = PromptVariant.new!(%{template: "v1", generation: 2})
      child = PromptVariant.create_child(parent, "v2 improved")

      assert child.generation == 3
    end

    test "creates child with parent in parents list" do
      parent = PromptVariant.new!(%{template: "v1"})
      child = PromptVariant.create_child(parent, "v2")

      assert child.parents == [parent.id]
    end

    test "child has new template" do
      parent = PromptVariant.new!(%{template: "original"})
      child = PromptVariant.create_child(parent, "mutated")

      assert child.template == "mutated"
    end

    test "child has unique id" do
      parent = PromptVariant.new!(%{template: "v1"})
      child = PromptVariant.create_child(parent, "v2")

      assert child.id != parent.id
      assert String.starts_with?(child.id, "pv_")
    end

    test "child metrics are nil" do
      parent = PromptVariant.new!(%{template: "v1"})
      parent = PromptVariant.update_metrics(parent, %{accuracy: 0.9, token_cost: 100})

      child = PromptVariant.create_child(parent, "v2")

      assert child.accuracy == nil
      assert child.token_cost == nil
    end
  end

  # ============================================================================
  # Comparison
  # ============================================================================

  describe "compare/3" do
    test "compares accuracy - higher is better" do
      v1 = %PromptVariant{id: "1", template: "a", accuracy: 0.9, token_cost: 100}
      v2 = %PromptVariant{id: "2", template: "b", accuracy: 0.8, token_cost: 100}

      assert PromptVariant.compare(v1, v2, :accuracy) == :gt
      assert PromptVariant.compare(v2, v1, :accuracy) == :lt
    end

    test "compares token_cost - lower is better" do
      v1 = %PromptVariant{id: "1", template: "a", accuracy: 0.9, token_cost: 100}
      v2 = %PromptVariant{id: "2", template: "b", accuracy: 0.9, token_cost: 200}

      assert PromptVariant.compare(v1, v2, :token_cost) == :gt
      assert PromptVariant.compare(v2, v1, :token_cost) == :lt
    end

    test "compares latency_ms - lower is better" do
      v1 = %PromptVariant{id: "1", template: "a", latency_ms: 100}
      v2 = %PromptVariant{id: "2", template: "b", latency_ms: 200}

      assert PromptVariant.compare(v1, v2, :latency_ms) == :gt
      assert PromptVariant.compare(v2, v1, :latency_ms) == :lt
    end

    test "returns :eq when values are equal" do
      v1 = %PromptVariant{id: "1", template: "a", accuracy: 0.9, token_cost: 100}
      v2 = %PromptVariant{id: "2", template: "b", accuracy: 0.9, token_cost: 100}

      assert PromptVariant.compare(v1, v2, :accuracy) == :eq
      assert PromptVariant.compare(v1, v2, :token_cost) == :eq
    end

    test "returns :eq when either value is nil" do
      v1 = %PromptVariant{id: "1", template: "a", accuracy: 0.9, token_cost: nil}
      v2 = %PromptVariant{id: "2", template: "b", accuracy: nil, token_cost: 100}

      assert PromptVariant.compare(v1, v2, :accuracy) == :eq
      assert PromptVariant.compare(v1, v2, :token_cost) == :eq
    end
  end

  # ============================================================================
  # Edge Cases
  # ============================================================================

  describe "edge cases" do
    test "handles very long template strings" do
      long_template = String.duplicate("a", 100_000)
      {:ok, variant} = PromptVariant.new(%{template: long_template})
      assert String.length(variant.template) == 100_000
    end

    test "handles deeply nested map templates" do
      template = %{
        level1: %{
          level2: %{
            level3: %{content: "deep"}
          }
        }
      }

      {:ok, variant} = PromptVariant.new(%{template: template})
      assert variant.template == template
    end

    test "handles zero accuracy and token_cost" do
      variant = PromptVariant.new!(%{template: "test"})
      updated = PromptVariant.update_metrics(variant, %{accuracy: 0.0, token_cost: 0})

      assert updated.accuracy == 0.0
      assert updated.token_cost == 0
      assert PromptVariant.evaluated?(updated)
    end
  end
end
