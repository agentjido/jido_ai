defmodule Jido.AI.Accuracy.UncertaintyResultTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.UncertaintyResult

  @moduletag :capture_log

  describe "new/1" do
    test "creates result with valid attributes" do
      assert {:ok, result} = UncertaintyResult.new(%{uncertainty_type: :aleatoric})

      assert result.uncertainty_type == :aleatoric
    end

    test "creates result with all attributes" do
      assert {:ok, result} =
               UncertaintyResult.new(%{
                 uncertainty_type: :epistemic,
                 confidence: 0.8,
                 reasoning: "Out of domain query",
                 suggested_action: :abstain
               })

      assert result.uncertainty_type == :epistemic
      assert result.confidence == 0.8
      assert result.reasoning == "Out of domain query"
      assert result.suggested_action == :abstain
    end

    test "returns error for invalid uncertainty type" do
      assert {:error, :invalid_uncertainty_type} =
               UncertaintyResult.new(%{uncertainty_type: :invalid})
    end

    test "accepts all valid uncertainty types" do
      types = [:aleatoric, :epistemic, :none]

      Enum.each(types, fn type ->
        assert {:ok, %UncertaintyResult{uncertainty_type: ^type}} =
                 UncertaintyResult.new(%{uncertainty_type: type})
      end)
    end

    test "sets default metadata to empty map" do
      assert {:ok, result} = UncertaintyResult.new(%{uncertainty_type: :none})

      assert result.metadata == %{}
    end
  end

  describe "new!/1" do
    test "creates result with valid attributes" do
      result = UncertaintyResult.new!(%{uncertainty_type: :aleatoric})
      assert result.uncertainty_type == :aleatoric
    end

    test "raises for invalid attributes" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        UncertaintyResult.new!(%{uncertainty_type: :invalid})
      end
    end
  end

  describe "type helpers" do
    test "aleatoric?/1 returns true for aleatoric type" do
      result = UncertaintyResult.new!(%{uncertainty_type: :aleatoric})
      assert UncertaintyResult.aleatoric?(result)
    end

    test "aleatoric?/1 returns false for other types" do
      result = UncertaintyResult.new!(%{uncertainty_type: :epistemic})
      refute UncertaintyResult.aleatoric?(result)
    end

    test "epistemic?/1 returns true for epistemic type" do
      result = UncertaintyResult.new!(%{uncertainty_type: :epistemic})
      assert UncertaintyResult.epistemic?(result)
    end

    test "epistemic?/1 returns false for other types" do
      result = UncertaintyResult.new!(%{uncertainty_type: :aleatoric})
      refute UncertaintyResult.epistemic?(result)
    end

    test "certain?/1 returns true for none type" do
      result = UncertaintyResult.new!(%{uncertainty_type: :none})
      assert UncertaintyResult.certain?(result)
    end

    test "certain?/1 returns false for uncertain types" do
      result = UncertaintyResult.new!(%{uncertainty_type: :aleatoric})
      refute UncertaintyResult.certain?(result)
    end

    test "uncertain?/1 returns true for any uncertainty" do
      aleatoric = UncertaintyResult.new!(%{uncertainty_type: :aleatoric})
      epistemic = UncertaintyResult.new!(%{uncertainty_type: :epistemic})

      assert UncertaintyResult.uncertain?(aleatoric)
      assert UncertaintyResult.uncertain?(epistemic)
    end

    test "uncertain?/1 returns false for certain" do
      result = UncertaintyResult.new!(%{uncertainty_type: :none})
      refute UncertaintyResult.uncertain?(result)
    end
  end

  describe "to_map/1" do
    test "converts result to map" do
      result = UncertaintyResult.new!(%{uncertainty_type: :aleatoric, confidence: 0.8})

      map = UncertaintyResult.to_map(result)

      assert Map.has_key?(map, "uncertainty_type")
      assert Map.has_key?(map, "confidence")
      assert map["uncertainty_type"] == :aleatoric
      assert map["confidence"] == 0.8
    end

    test "excludes nil and empty values" do
      result = UncertaintyResult.new!(%{uncertainty_type: :aleatoric})

      map = UncertaintyResult.to_map(result)

      assert Map.has_key?(map, "uncertainty_type")
      refute Map.has_key?(map, "reasoning")
      refute Map.has_key?(map, "suggested_action")
    end
  end

  describe "from_map/1" do
    test "creates result from map" do
      map = %{"uncertainty_type" => "aleatoric", "confidence" => 0.8}

      assert {:ok, result} = UncertaintyResult.from_map(map)
      assert result.uncertainty_type == :aleatoric
      assert result.confidence == 0.8
    end

    test "creates result with all attributes" do
      map = %{
        "uncertainty_type" => "epistemic",
        "confidence" => 0.7,
        "reasoning" => "Test"
      }

      assert {:ok, result} = UncertaintyResult.from_map(map)
      assert result.uncertainty_type == :epistemic
      assert result.confidence == 0.7
    end

    test "returns error for invalid data" do
      map = %{"uncertainty_type" => "invalid"}

      assert {:error, :invalid_uncertainty_type} = UncertaintyResult.from_map(map)
    end
  end

  describe "round trip serialization" do
    test "to_map and from_map are inverses" do
      original =
        UncertaintyResult.new!(%{
          uncertainty_type: :epistemic,
          confidence: 0.7,
          reasoning: "Test"
        })

      map = UncertaintyResult.to_map(original)
      {:ok, restored} = UncertaintyResult.from_map(map)

      assert restored.uncertainty_type == original.uncertainty_type
      assert restored.confidence == original.confidence
    end
  end
end
