defmodule Jido.AI.Streaming.IDTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Streaming.ID

  describe "generate/0 and validate/1" do
    test "generates valid UUID v4 format" do
      stream_id = ID.generate()
      assert {:ok, ^stream_id} = ID.validate(stream_id)
    end

    test "generates unique IDs" do
      ids = Enum.map(1..100, fn _ -> ID.generate() end)
      assert length(Enum.uniq(ids)) == 100
    end

    test "accepts valid UUID v4 strings" do
      valid_uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert {:ok, ^valid_uuid} = ID.validate(valid_uuid)
    end

    test "rejects invalid IDs" do
      assert {:error, :invalid_stream_id_format} = ID.validate("not-a-uuid")
      assert {:error, :invalid_stream_id_type} = ID.validate(nil)
    end
  end
end
