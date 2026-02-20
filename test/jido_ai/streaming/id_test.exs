defmodule Jido.AI.Streaming.IDTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Streaming.ID

  test "generate_stream_id/0 produces UUID v4 format and unique values" do
    id = ID.generate_stream_id()
    assert {:ok, ^id} = ID.validate_stream_id(id)

    ids = Enum.map(1..50, fn _ -> ID.generate_stream_id() end)
    assert length(Enum.uniq(ids)) == 50
  end

  test "validate_stream_id/1 rejects invalid values" do
    assert {:error, :invalid_stream_id_format} = ID.validate_stream_id("not-a-uuid")
    assert {:error, :invalid_stream_id_type} = ID.validate_stream_id(nil)
  end
end
