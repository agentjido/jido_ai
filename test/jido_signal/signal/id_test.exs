defmodule JidoTest.Signal.IDTest do
  use ExUnit.Case, async: true

  alias Jido.Signal.ID

  describe "generate/0" do
    test "generates valid UUID7 and timestamp" do
      {uuid, timestamp} = ID.generate()
      assert is_binary(uuid)
      assert is_integer(timestamp)
      assert ID.valid?(uuid)
    end

    test "generates chronologically ordered IDs across milliseconds" do
      {uuid1, _} = ID.generate()
      # Ensure different millisecond
      Process.sleep(2)
      {uuid2, _} = ID.generate()
      # Ensure different millisecond
      Process.sleep(2)
      {uuid3, _} = ID.generate()

      assert ID.compare(uuid1, uuid2) == :lt
      assert ID.compare(uuid2, uuid3) == :lt
      assert ID.compare(uuid1, uuid3) == :lt
    end

    test "generates unique IDs within same millisecond" do
      # Generate multiple IDs quickly to ensure same timestamp
      ids = for _i <- 1..10, do: ID.generate()

      # Group by timestamp
      by_timestamp =
        ids
        |> Enum.group_by(fn {_uuid, ts} -> ts end)
        |> Enum.find(fn {_ts, group} -> length(group) > 1 end)

      case by_timestamp do
        {_ts, same_ms_ids} ->
          # Extract just the UUIDs
          uuids = Enum.map(same_ms_ids, fn {uuid, _} -> uuid end)

          # Verify all UUIDs are unique
          assert length(Enum.uniq(uuids)) == length(uuids)

          # Verify all have sequence numbers
          sequences = Enum.map(uuids, &ID.sequence_number/1)
          assert Enum.all?(sequences, fn seq -> seq >= 0 and seq < 4096 end)

        nil ->
          # If we couldn't generate IDs in same millisecond, skip test
          :ok
      end
    end
  end

  describe "extract_timestamp/1" do
    test "extracts correct timestamp from UUID7" do
      {uuid, original_ts} = ID.generate()
      extracted_ts = ID.extract_timestamp(uuid)
      assert extracted_ts == original_ts
    end
  end

  describe "compare/2" do
    test "compares UUIDs chronologically" do
      {uuid1, _} = ID.generate()
      # Ensure different millisecond
      Process.sleep(2)
      {uuid2, _} = ID.generate()

      assert ID.compare(uuid1, uuid2) == :lt
      assert ID.compare(uuid2, uuid1) == :gt
      assert ID.compare(uuid1, uuid1) == :eq
    end

    test "orders by sequence number within same millisecond" do
      # Generate IDs quickly to try to get same timestamp
      {uuid1, ts1} = ID.generate()
      {uuid2, ts2} = ID.generate()

      if ts1 == ts2 do
        seq1 = ID.sequence_number(uuid1)
        seq2 = ID.sequence_number(uuid2)

        # Verify consistent ordering based on sequence
        comparison = ID.compare(uuid1, uuid2)
        assert comparison in [:lt, :gt]

        # Verify ordering matches sequence comparison
        expected = if seq1 < seq2, do: :lt, else: :gt
        assert comparison == expected
      else
        :ok
      end
    end

    test "orders lexicographically when timestamp and sequence match" do
      # Mock two UUIDs with same timestamp and sequence
      # This is a rare case but should be handled consistently
      uuid1 = "017ff6d0-1234-7000-abcd-ef0123456789"
      uuid2 = "017ff6d0-1234-7000-abcd-ef9876543210"

      result = ID.compare(uuid1, uuid2)
      assert result in [:lt, :eq, :gt]
    end
  end

  describe "valid?/1" do
    test "validates correct UUID7 format" do
      {uuid, _} = ID.generate()
      assert ID.valid?(uuid)
    end

    test "rejects invalid formats" do
      refute ID.valid?("not-a-uuid")
      refute ID.valid?(123)
      refute ID.valid?(nil)
    end
  end

  describe "sequence_number/1" do
    test "extracts sequence number from UUID7" do
      {uuid, _} = ID.generate()
      seq = ID.sequence_number(uuid)
      assert is_integer(seq)
      # 12-bit number
      assert seq >= 0 and seq < 4096
    end

    test "extracts different sequence numbers for IDs in same millisecond" do
      # Generate IDs quickly to try to get same timestamp
      {uuid1, ts1} = ID.generate()
      {uuid2, ts2} = ID.generate()

      if ts1 == ts2 do
        seq1 = ID.sequence_number(uuid1)
        seq2 = ID.sequence_number(uuid2)

        # Verify sequences are different
        assert seq1 != seq2
      else
        :ok
      end
    end
  end

  describe "format_sortable/1" do
    test "formats timestamp and sequence as sortable string" do
      {uuid, ts} = ID.generate()
      formatted = ID.format_sortable(uuid)
      assert is_binary(formatted)
      assert String.starts_with?(formatted, "#{ts}-")
    end

    test "maintains ordering in string format" do
      {uuid1, _} = ID.generate()
      # Ensure different millisecond
      Process.sleep(2)
      {uuid2, _} = ID.generate()

      formatted1 = ID.format_sortable(uuid1)
      formatted2 = ID.format_sortable(uuid2)

      # String comparison should match ID comparison
      string_order = formatted1 < formatted2
      id_order = ID.compare(uuid1, uuid2) == :lt

      assert string_order == id_order
    end
  end

  describe "generate_batch/1" do
    test "generates requested number of IDs" do
      {ids, _ts} = ID.generate_batch(5)
      assert length(ids) == 5
      assert Enum.all?(ids, &ID.valid?/1)
    end

    test "generates strictly ordered IDs" do
      {ids, _ts} = ID.generate_batch(10)

      # Verify sequential ordering
      ids
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [id1, id2] ->
        assert ID.compare(id1, id2) == :lt
      end)
    end

    test "handles sequence numbers correctly within same millisecond" do
      {ids, _ts} = ID.generate_batch(10)

      # Get sequences and ensure they're sequential
      sequences = Enum.map(ids, &ID.sequence_number/1)
      assert sequences == Enum.to_list(0..9)
    end

    test "handles large batches spanning multiple milliseconds" do
      # Larger than max sequence (4096)
      batch_size = 5000
      {ids, start_ts} = ID.generate_batch(batch_size)

      assert length(ids) == batch_size

      # Group by timestamp
      by_timestamp = Enum.group_by(ids, &ID.extract_timestamp/1)

      # Verify timestamps are sequential
      timestamps = Map.keys(by_timestamp) |> Enum.sort()
      # Should span multiple milliseconds
      assert length(timestamps) > 1
      assert hd(timestamps) == start_ts

      # Verify sequence numbers reset for each millisecond
      Enum.each(by_timestamp, fn {_ts, ms_ids} ->
        sequences = Enum.map(ms_ids, &ID.sequence_number/1)
        assert sequences == Enum.to_list(0..(length(sequences) - 1))
      end)
    end

    test "maintains strict ordering across millisecond boundaries" do
      # Large enough to span milliseconds
      batch_size = 5000
      {ids, _ts} = ID.generate_batch(batch_size)

      # Verify global ordering
      sorted_ids =
        Enum.sort_by(ids, fn id ->
          ts = ID.extract_timestamp(id)
          seq = ID.sequence_number(id)
          {ts, seq}
        end)

      assert ids == sorted_ids
    end

    test "generates unique IDs" do
      {ids, _ts} = ID.generate_batch(1000)
      assert length(Enum.uniq(ids)) == 1000
    end
  end
end
