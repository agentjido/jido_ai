defmodule ReqLLM.Coverage.Anthropic.SimpleObjectTest do
  @moduledoc """
  Minimal Anthropic object generation test to verify the streaming fix works
  with the fixture system.
  """

  use ExUnit.Case, async: false

  import ReqLLM.Test.LiveFixture

  @moduletag :coverage
  @moduletag :anthropic

  describe "anthropic object generation fix" do
    test "basic object generation works" do
      schema = [
        name: [type: :string, required: true, doc: "Person's full name"],
        age: [type: :pos_integer, required: true, doc: "Person's age in years"],
        occupation: [type: :string, doc: "Person's job or profession"]
      ]

      result =
        use_fixture(:anthropic, "simple_basic_object", fn ->
          ReqLLM.generate_object(
            "anthropic:claude-3-5-sonnet-20241022",
            "Generate a fictional character",
            schema
          )
        end)

      {:ok, response} = result

      # Verify response structure
      assert response.message
      assert response.message.content

      # Extract and verify object
      object = ReqLLM.Response.object(response)
      assert is_map(object)
      assert map_size(object) > 0

      # Verify required fields
      assert Map.has_key?(object, "name")
      assert Map.has_key?(object, "age")
      assert is_binary(object["name"])
      assert object["name"] != ""
      assert is_integer(object["age"])
      assert object["age"] > 0
    end

    test "streaming object generation works and returns complete objects" do
      schema = [
        name: [type: :string, required: true, doc: "Character name"],
        role: [type: :string, required: true, doc: "Character role"],
        level: [type: :pos_integer, required: true, doc: "Character level"]
      ]

      result =
        use_fixture(:anthropic, "simple_streaming_object", fn ->
          ReqLLM.stream_object(
            "anthropic:claude-3-5-sonnet-20241022",
            "Generate a fantasy character",
            schema
          )
        end)

      {:ok, response} = result

      if ReqLLM.Test.LiveFixture.live_mode?() do
        # Live mode: test actual streaming with JSON delta accumulation
        assert response.stream?

        # Get the object stream and collect objects
        objects =
          response
          |> ReqLLM.Response.object_stream()
          |> Enum.to_list()

        # Should have at least one object
        assert length(objects) >= 1

        # Verify the first object is NOT empty (key test for the fix)
        [first_object | _] = objects
        assert is_map(first_object)
        assert map_size(first_object) > 0

        # This is the critical assertion: proves JSON delta accumulation works
        refute first_object == %{}

        # Verify required fields
        assert Map.has_key?(first_object, "name")
        assert Map.has_key?(first_object, "role")
        assert Map.has_key?(first_object, "level")

        assert is_binary(first_object["name"])
        assert first_object["name"] != ""
        assert is_binary(first_object["role"])
        assert first_object["role"] != ""
        assert is_integer(first_object["level"])
        assert first_object["level"] > 0
      else
        # Cached mode: verify materialized object
        object = ReqLLM.Response.object(response)

        assert is_map(object)
        assert map_size(object) > 0
        refute object == %{}

        # Basic field validation
        assert Map.has_key?(object, "name")
        assert is_binary(object["name"])
        assert object["name"] != ""
      end
    end
  end
end
