defmodule Jido.Signal.ID do
  @moduledoc """
  Manages UUID7-based signal IDs for the bus system. Provides utilities for
  generating, comparing, and extracting information from signal IDs.

  UUID7s provide several benefits for signal IDs:
  - Monotonically increasing (timestamp-based)
  - Contain embedded timestamps and sequence numbers
  - High uniqueness guarantees within the same millisecond
  - Good sequential scanning performance

  UUID7 Format:
  - First 48 bits: Unix timestamp in milliseconds
  - Next 12 bits: Sequence number (monotonic counter within each millisecond)
  - Remaining bits: Random data

  This ensures that:
  1. IDs are globally ordered by timestamp
  2. IDs generated in the same millisecond are ordered by sequence number
  3. IDs with same timestamp and sequence are ordered lexicographically

  ## Usage Examples

      # Generate UUID7
      {id, timestamp} = Jido.Signal.ID.generate()

      # Compare IDs chronologically
      :lt = Jido.Signal.ID.compare(older_id, newer_id)

      # Extract components
      timestamp = Jido.Signal.ID.extract_timestamp(id)
      sequence = Jido.Signal.ID.sequence_number(id)
  """

  @type uuid7 :: String.t()
  @type timestamp :: non_neg_integer()
  @type comparison_result :: :lt | :eq | :gt

  @doc """
  Generates a new signal ID using UUID7.

  Returns a tuple containing the generated ID and its embedded timestamp.
  The timestamp is in Unix milliseconds.

  ## Examples

      {id, ts} = Jido.Signal.ID.generate()
      #=> {"018df6f0-1234-7890-abcd-ef0123456789", 1677721600000}
  """
  @spec generate() :: {uuid7(), timestamp()}
  def generate do
    uuid = Uniq.UUID.uuid7()
    timestamp = extract_timestamp(uuid)
    {uuid, timestamp}
  end

  @doc """
  Generates a new signal ID using UUID7, returning just the UUID string.

  ## Examples

      id = Jido.Signal.ID.generate!()
      #=> "018df6f0-1234-7890-abcd-ef0123456789"
  """
  @spec generate!() :: uuid7()
  def generate! do
    {uuid, _timestamp} = generate()
    uuid
  end

  @doc """
  Generates a UUID7 with a specific timestamp and sequence number.
  This ensures strict ordering of IDs within the same millisecond.

  ## Parameters
    * timestamp - Unix timestamp in milliseconds
    * sequence - A number between 0 and 4095 (12 bits)

  ## Examples
      id = Jido.Signal.ID.generate_sequential(timestamp, 1)
      #=> "018df6f0-0001-7890-abcd-ef0123456789"
  """
  @spec generate_sequential(timestamp(), non_neg_integer()) :: uuid7()
  def generate_sequential(timestamp, sequence) when sequence >= 0 and sequence < 4096 do
    # Convert timestamp to 48 bits
    ts = timestamp
    # Version 7 (4 bits)
    version = 7
    # Convert sequence to 12 bits
    seq = sequence
    # RFC variant (2 bits set to 1,0)
    # 0b10
    variant = 2
    # Generate 62 bits of random data
    random = :crypto.strong_rand_bytes(8)
    <<rand_a::size(62), _::size(2)>> = random

    # Combine into UUID7 format:
    # - 48 bits timestamp
    # - 4 bits version (7)
    # - 12 bits sequence
    # - 2 bits variant (0b10)
    # - 62 bits random
    raw = <<
      ts::unsigned-size(48),
      version::unsigned-size(4),
      seq::unsigned-size(12),
      variant::unsigned-size(2),
      rand_a::unsigned-size(62)
    >>

    # Format as UUID string
    raw
    |> Base.encode16(case: :lower)
    |> uuid7_format()
  end

  @doc """
  Extracts the Unix timestamp (in milliseconds) from a UUID7 string.
  UUID7 embeds a 48-bit timestamp in its first 6 bytes.

  ## Examples

      ts = Jido.Signal.ID.extract_timestamp("018df6f0-1234-7890-abcd-ef0123456789")
      #=> 1677721600000
  """
  @spec extract_timestamp(uuid7()) :: timestamp()
  def extract_timestamp(uuid) when is_binary(uuid) do
    # Convert UUID string to raw bytes
    {:ok, <<timestamp::48, _rest::binary>>} =
      Base.decode16(String.replace(uuid, "-", ""), case: :mixed)

    timestamp
  end

  @doc """
  Compares two UUID7s chronologically.
  Returns `:lt`, `:eq`, or `:gt` based on the following order:
  1. Timestamp comparison
  2. If timestamps match, sequence number comparison
  3. If both match, lexicographical comparison of remaining bits

  ## Examples

      Jido.Signal.ID.compare(older_id, newer_id)
      #=> :lt

      Jido.Signal.ID.compare(newer_id, older_id)
      #=> :gt

      Jido.Signal.ID.compare(id, id)
      #=> :eq
  """
  @spec compare(uuid7(), uuid7()) :: comparison_result()
  def compare(uuid1, uuid2) when is_binary(uuid1) and is_binary(uuid2) do
    ts1 = extract_timestamp(uuid1)
    ts2 = extract_timestamp(uuid2)

    cond do
      ts1 < ts2 -> :lt
      ts1 > ts2 -> :gt
      true -> compare_sequence(uuid1, uuid2)
    end
  end

  @doc """
  Validates that a string is a valid UUID7.
  Returns true if the input is a valid UUID7 string, false otherwise.

  ## Examples

      Jido.Signal.ID.valid?("018df6f0-1234-7890-abcd-ef0123456789")
      #=> true

      Jido.Signal.ID.valid?("not-a-uuid")
      #=> false
  """
  @spec valid?(term()) :: boolean()
  def valid?(uuid) when is_binary(uuid) do
    Uniq.UUID.valid?(uuid)
  end

  def valid?(_), do: false

  @doc """
  Returns the sequence number portion of the UUID7.
  This is a 12-bit monotonic counter within each millisecond.

  ## Examples

      seq = Jido.Signal.ID.sequence_number("018df6f0-1234-7890-abcd-ef0123456789")
      #=> 42
  """
  @spec sequence_number(uuid7()) :: non_neg_integer()
  def sequence_number(uuid) when is_binary(uuid) do
    raw = String.replace(uuid, "-", "")
    {:ok, binary} = Base.decode16(raw, case: :mixed)

    <<_ts::unsigned-integer-size(48), _version::unsigned-integer-size(4),
      seq::unsigned-integer-size(12), _rest::bits>> = binary

    seq
  end

  @doc """
  Formats a timestamp and sequence as a sortable string.
  Useful for version strings or ordering.

  Returns a string in the format "timestamp-sequence".

  ## Examples

      Jido.Signal.ID.format_sortable("018df6f0-1234-7890-abcd-ef0123456789")
      #=> "1677721600000-42"
  """
  @spec format_sortable(uuid7()) :: String.t()
  def format_sortable(uuid) when is_binary(uuid) do
    raw = String.replace(uuid, "-", "")
    {:ok, binary} = Base.decode16(raw, case: :mixed)
    <<timestamp::48, seq::12, _::68>> = binary
    "#{timestamp}-#{seq}"
  end

  @doc """
  Generates multiple sequential UUIDs in a batch.
  All UUIDs will be strictly ordered and unique within the same millisecond.
  If the batch size would exceed the available sequence numbers (4096),
  it will use multiple milliseconds.

  ## Examples

      {ids, timestamp} = Jido.Signal.ID.generate_batch(5)
      #=> {["018df6f0-0001-...", "018df6f0-0002-..."], 1677721600000}

      # Verify ordering
      [id1, id2 | _] = ids
      :lt = Jido.Signal.ID.compare(id1, id2)
  """
  @spec generate_batch(pos_integer()) :: {[uuid7()], timestamp()}
  def generate_batch(count) when count > 0 do
    timestamp = System.system_time(:millisecond)
    {ids, _final_ts} = do_generate_batch(count, timestamp, 0, [])
    {Enum.reverse(ids), timestamp}
  end

  # Private Helpers

  defp do_generate_batch(0, timestamp, _seq, acc), do: {acc, timestamp}

  defp do_generate_batch(count, timestamp, seq, acc) when seq >= 4096 do
    # Sequence exhausted, move to next millisecond
    do_generate_batch(count, timestamp + 1, 0, acc)
  end

  defp do_generate_batch(count, timestamp, seq, acc) do
    id = generate_sequential(timestamp, seq)
    do_generate_batch(count - 1, timestamp, seq + 1, [id | acc])
  end

  @spec compare_sequence(uuid7(), uuid7()) :: comparison_result()
  defp compare_sequence(uuid1, uuid2) do
    seq1 = sequence_number(uuid1)
    seq2 = sequence_number(uuid2)

    cond do
      seq1 < seq2 -> :lt
      seq1 > seq2 -> :gt
      # If sequence numbers match, compare remaining bits lexicographically
      true -> compare_raw(uuid1, uuid2)
    end
  end

  @spec compare_raw(uuid7(), uuid7()) :: comparison_result()
  defp compare_raw(uuid1, uuid2) do
    # Lexicographical comparison of raw UUIDs when timestamps and sequences match
    raw1 = String.replace(uuid1, "-", "")
    raw2 = String.replace(uuid2, "-", "")

    cond do
      raw1 < raw2 -> :lt
      raw1 > raw2 -> :gt
      true -> :eq
    end
  end

  # Format a raw hex string into UUID7 format with hyphens
  defp uuid7_format(
         <<a::8, b::8, c::8, d::8, e::8, f::8, g::8, h::8, i::8, j::8, k::8, l::8, m::8, n::8,
           o::8, p::8, q::8, r::8, s::8, t::8, u::8, v::8, w::8, x::8, y::8, z::8, aa::8, bb::8,
           cc::8, dd::8, ee::8, ff::8>>
       ) do
    <<a, b, c, d, e, f, g, h>> <>
      "-" <>
      <<i, j, k, l>> <>
      "-" <>
      <<m, n, o, p>> <>
      "-" <>
      <<q, r, s, t>> <>
      "-" <>
      <<u, v, w, x, y, z, aa, bb, cc, dd, ee, ff>>
  end
end
