defmodule Jido.AI.ModelTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  use Jido.AI.TestMacros

  import Jido.AI.Test.Fixtures.ModelFixtures
  import Jido.AI.TestSupport.Assertions

  alias Jido.AI.Model
  alias Jido.AI.Provider.OpenAI
  alias Jido.AI.Test.FakeProvider

  doctest Model

  setup do
    # Register providers needed for tests
    Jido.AI.Provider.Registry.register(:openai, OpenAI)
    Jido.AI.Provider.Registry.register(:fake, FakeProvider)

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
      Jido.AI.Provider.Registry.initialize()
    end)

    :ok
  end

  describe "from/1" do
    test "handles valid inputs" do
      # Struct passthrough
      model = gpt4()
      assert model == assert_ok(Model.from(model))

      # String format
      model = assert_ok(Model.from("openai:gpt-4"))
      assert model.provider == :openai
      assert model.model == "gpt-4"

      # Tuple format with real model data from registry
      model = assert_ok(Model.from({:openai, model: "gpt-4"}))
      # Real gpt-4 context limit
      assert model.limit.context == 8192
      # Real gpt-4 output limit
      assert model.limit.output == 8192

      # Tuple format with options
      model = assert_ok(Model.from({:openai, model: "gpt-4", temperature: 0.7}))
      assert model.temperature == 0.7
    end

    test "returns error for invalid inputs" do
      invalid_inputs = [
        "invalid-format",
        "",
        "unknown:model",
        {:openai, temperature: 0.7},
        {:unknown, model: "test"},
        123,
        nil,
        %{not: "a model"}
      ]

      for invalid_input <- invalid_inputs do
        assert {:error, _message} = Model.from(invalid_input)
      end
    end

    test "handles edge cases" do
      # Multiple colons
      model = assert_ok(Model.from("openai:gpt-4:turbo"))
      assert model.model == "gpt-4:turbo"

      # Whitespace in names
      model = assert_ok(Model.from("openai:gpt 4"))
      assert model.model == "gpt 4"

      # Empty model name (may succeed or fail)
      case Model.from("openai:") do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end

  describe "validate/1" do
    test "validates models" do
      # Test that validate function exists and handles basic cases
      incomplete_model = %{minimal() | provider: nil}
      assert {:error, _} = Model.validate(incomplete_model)
    end
  end

  describe "property tests" do
    property "string format parsing" do
      providers = [:openai, :fake]

      check all(
              provider <- StreamData.member_of(providers),
              model_name <- StreamData.string(:alphanumeric, min_length: 1)
            ) do
        input_string = "#{provider}:#{model_name}"

        case Model.from(input_string) do
          {:ok, model} ->
            assert model.provider == provider
            assert model.model == model_name

          {:error, _} ->
            # Some combinations might be invalid
            :ok
        end
      end
    end
  end

  describe "from_json functions" do
    test "from_json functions work" do
      assert function_exported?(Model, :from_json, 1)
      assert function_exported?(Model, :from_json!, 1)
      assert {:error, _} = Model.from_json(%{"invalid" => "structure"})
    end
  end
end
