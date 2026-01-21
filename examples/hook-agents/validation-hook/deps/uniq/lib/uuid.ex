defmodule Uniq.UUID do
  @moduledoc """
  This module provides RFC 4122 compliant universally unique identifiers (UUIDs).

  See the [README](README.md) for general usage information.
  """
  import Bitwise, except: ["~~~": 1, &&&: 2, |||: 2, "^^^": 2, <<<: 2, >>>: 2]
  import Kernel, except: [to_string: 1]

  defstruct [:format, :version, :variant, :time, :seq, :node, :bytes]

  @type t :: <<_::128>>
  @type formatted ::
          t
          | <<_::360>>
          | <<_::288>>
          | <<_::256>>
          | <<_::176>>
  @type format :: :default | :raw | :hex | :urn | :slug
  @type namespace :: :dns | :url | :oid | :x500 | nil | formatted

  @type info :: %__MODULE__{
          format: :raw | :hex | :default | :urn | :slug,
          version: 1..8,
          variant: bitstring,
          time: non_neg_integer,
          seq: non_neg_integer,
          node: <<_::48>>,
          bytes: t
        }

  @formats [:default, :raw, :hex, :urn, :slug]
  @namespaces [:dns, :url, :oid, :x500, nil]

  # Namespaces
  @dns_namespace_id Base.decode16!("6ba7b8109dad11d180b400c04fd430c8", case: :lower)
  @url_namespace_id Base.decode16!("6ba7b8119dad11d180b400c04fd430c8", case: :lower)
  @oid_namespace_id Base.decode16!("6ba7b8129dad11d180b400c04fd430c8", case: :lower)
  @x500_namespace_id Base.decode16!("6ba7b8149dad11d180b400c04fd430c8", case: :lower)
  @nil_id <<0::128>>

  # Variants
  @reserved_ncs <<0::1>>
  @rfc_variant <<2::2>>
  @reserved_ms <<6::3>>
  @reserved_future <<7::3>>

  defmacrop bits(n), do: quote(do: bitstring - size(unquote(n)))
  defmacrop bytes(n), do: quote(do: binary - size(unquote(n)))
  defmacrop uint(n), do: quote(do: unsigned - integer - size(unquote(n)))
  defmacrop biguint(n), do: quote(do: big - unsigned - integer - size(unquote(n)))

  @doc """
  Generates a UUID using the version 1 scheme, as described in RFC 4122

  This scheme is based on a few key properties:

  * A timestamp, based on the count of 100-nanosecond intervals since the start of
  the Gregorian calendar, i.e. October 15th, 1582, in Coordinated Universal Time (UTC).
  * A clock sequence number, used to ensure that UUIDs generated with the same timestamp
  are still unique, by incrementing the sequence each time a UUID is generated with the
  same timestamp as the last UUID that was generated. This sequence is initialized with
  random bytes at startup, to protect against conflicts.
  * A node identifier, which is based on the MAC address of one of the network interfaces
  on the system, or if unavailable, using random bytes. In our case, we specifically look
  for the first network interface returned by `:inet.getifaddrs/0` that is up, broadcastable,
  and has a hardware address, otherwise falling back to cryptographically strong random bytes.
  """
  @spec uuid1() :: formatted
  @spec uuid1(format) :: formatted
  def uuid1(format \\ :default) do
    {time, clock} = Uniq.Generator.next()

    uuid1(time, clock, mac_address(), format)
  end

  @doc """
  This function is the same as `uuid/1`, except the caller provides the clock sequence
  value and the node identifier (which must be a 6-byte binary).

  See `uuid/1` for details.
  """
  @spec uuid1(clock_seq :: non_neg_integer, node :: <<_::48>>, format) :: formatted
  def uuid1(clock_seq, <<node::bits(48)>>, format \\ :default)
      when is_integer(clock_seq) and format in @formats do
    {time, _} = Uniq.Generator.next()

    uuid1(time, clock_seq, node, format)
  end

  defp uuid1(time, clock_seq, node, format) do
    <<thi::12, tmid::16, tlo::32>> = <<time::biguint(60)>>

    # Encode version into high bits of timestamp
    thi = bor(thi, bsl(1, 12))

    # Encode variant into high bits of clock sequence
    clock_hi = bsr(band(clock_seq, 0x3F00), 8)
    clock_hi = bor(clock_hi, 0x80)
    clock_lo = band(clock_seq, 0xFF)

    raw = <<tlo::32, tmid::16, thi::16, clock_hi::8, clock_lo::8, node::bits(48)>>

    format(raw, format)
  end

  @doc """
  Generates a UUID using the version 3 scheme, as described in RFC 4122

  This scheme provides the means for generating UUIDs deterministically,
  given a namespace and a name. This means that with the same inputs, you
  get the same UUID as output.

  The main difference between this and the version 5 scheme, is that version 3
  uses MD5 for hashing, and version 5 uses SHA1. Both hashes are deprecated these
  days, but you should prefer version 5 unless otherwise required.

  In this scheme, the timestamp, clock sequence and node value are constructed
  from the namespace and name, as described in RFC 4122, Section 4.3.

  ## Namespaces

  You may choose one of several options for namespacing your UUIDs:

  1. Use a predefined namespace. These are provided by RFC 4122 in order to provide
  namespacing for common types of names. See below.
  2. Use your own namespace. For this, simply generate a UUID to represent the namespace.
  You may provide this UUID in whatever format is supported by `parse/1`.
  3. Use `nil`. This is bound to a special-case UUID that has no intrinsic meaning, but is
  valid for use as a namespace.

  The set of predefined namespaces consist of the following:

  * `:dns`, intended for namespacing fully-qualified domain names
  * `:url`, intended for namespacing URLs
  * `:oid`, intended for namespacing ISO OIDs
  * `:x500`, intended for namespacing X.500 DNs (in DER or text output format)

  ## Notes

  One thing to be aware of with version 3 and 5 UUIDs, is that unlike version 1 and 6,
  the lexicographical ordering of UUIDs of generated one after the other, is entirely
  random, as the most significant bits are dependent upon the hash of the namespace and
  name, and thus not based on time or even the lexicographical ordering of the name.

  This is generally worth the tradeoff in favor of determinism, but it is something to
  be aware of.

  Likewise, since the generation is deterministic, care must be taken to ensure that you
  do not try to use the same name for two different objects within the same namespace. This
  should be obvious, but since the other schemes are _not_ sensitive in this way, it is worth
  calling out.
  """
  @spec uuid3(namespace, name :: binary) :: formatted
  @spec uuid3(namespace, name :: binary, format) :: formatted
  def uuid3(namespace, name, format \\ :default)
      when (namespace in @namespaces or is_binary(namespace)) and is_binary(name) and
             format in @formats do
    namespaced_uuid(3, :md5, namespace, name, format)
  end

  @doc """
  Generates a UUID using the version 4 scheme, as described in RFC 4122

  This scheme is like the version 1 scheme, except it uses randomly generated data
  for the timestamp, clock sequence, and node fields.

  This scheme is the closest you can get to truly unique identifiers, as they are based
  on truly random (or pseudo-random) data, so the chances of generating the same UUID
  twice is astronomically small.

  ## Notes

  The version 4 scheme does have some deficiencies. Namely, since they are based on random
  data, the lexicographical ordering of the resulting UUID is itself random, which can play havoc
  with database indices should you choose to use UUIDs for primary keys.

  It is strongly recommended to consider the version 6 scheme instead. They are almost the
  same as a version 1 UUID, but with improved semantics that combine some of the beneficial
  traits of version 4 UUIDs without the lexicographical ordering downsides. The only caveat
  to that recommendation is if you need to pass them through a system that inspects the UUID
  encoding itself and doesn't have preliminary support for version 6.
  """
  @spec uuid4() :: formatted
  @spec uuid4(format) :: formatted
  def uuid4(format \\ :default) when format in @formats do
    <<tlo_mid::48, _::4, thi::12, _::2, rest::62>> = :crypto.strong_rand_bytes(16)

    raw = <<tlo_mid::48, 4::biguint(4), thi::12, @rfc_variant, rest::62>>

    format(raw, format)
  end

  @doc """
  Generates a UUID using the version 5 scheme, as described in RFC 4122

  This scheme provides the means for generating UUIDs deterministically,
  given a namespace and a name. This means that with the same inputs, you
  get the same UUID as output.

  The main difference between this and the version 5 scheme, is that version 3
  uses MD5 for hashing, and version 5 uses SHA1. Both hashes are deprecated these
  days, but you should prefer version 5 unless otherwise required.

  In this scheme, the timestamp, clock sequence and node value are constructed
  from the namespace and name, as described in RFC 4122, Section 4.3.

  ## Namespaces

  You may choose one of several options for namespacing your UUIDs:

  1. Use a predefined namespace. These are provided by RFC 4122 in order to provide
  namespacing for common types of names. See below.
  2. Use your own namespace. For this, simply generate a UUID to represent the namespace.
  You may provide this UUID in whatever format is supported by `parse/1`.
  3. Use `nil`. This is bound to a special-case UUID that has no intrinsic meaning, but is
  valid for use as a namespace.

  The set of predefined namespaces consist of the following:

  * `:dns`, intended for namespacing fully-qualified domain names
  * `:url`, intended for namespacing URLs
  * `:oid`, intended for namespacing ISO OIDs
  * `:x500`, intended for namespacing X.500 DNs (in DER or text output format)

  ## Notes

  One thing to be aware of with version 3 and 5 UUIDs, is that unlike version 1 and 6,
  the lexicographical ordering of UUIDs of generated one after the other, is entirely
  random, as the most significant bits are dependent upon the hash of the namespace and
  name, and thus not based on time or even the lexicographical ordering of the name.

  This is generally worth the tradeoff in favor of determinism, but it is something to
  be aware of.

  Likewise, since the generation is deterministic, care must be taken to ensure that you
  do not try to use the same name for two different objects within the same namespace. This
  should be obvious, but since the other schemes are _not_ sensitive in this way, it is worth
  calling out.
  """
  @spec uuid5(namespace, name :: binary) :: formatted
  @spec uuid5(namespace, name :: binary, format) :: formatted
  def uuid5(namespace, name, format \\ :default)
      when (namespace in @namespaces or is_binary(namespace)) and is_binary(name) and
             format in @formats do
    namespaced_uuid(5, :sha, namespace, name, format)
  end

  @doc """
  Generates a UUID using the proposed version 6 scheme, found
  [here](https://datatracker.ietf.org/doc/html/draft-peabody-dispatch-new-uuid-format-04#section-5.1).
  This is a draft extension of RFC 4122, but has not yet been formally accepted.

  Version 6 provides the following benefits over versions 1 and 4:

  * Like version 1, it is time-based, but unlike version 1, it is naturally sortable by time
  in its raw binary encoded form
  * Like version 4, it provides better guarantees of uniqueness and privacy, by basing itself
  on random or pseudo-random data, rather than MAC addresses and other potentially sensitive
  information.
  * Unlike version 4, which tends to interact poorly with database indices due to being derived
  entirely from random or pseudo-random data; version 6 ensures that the most significant bits
  of the binary encoded form are a 1:1 match with the most significant bits of the timestamp on
  which it was derived. This guarantees that version 6 UUIDs are naturally sortable in the order
  in which they were generated (with some randomness among those which are generated at the same
  time).

  There have been a number of similar proposals that address the same set of flaws. For example:

  * [KSUID](https://github.com/segmentio/ksuid)
  * [ULID](https://github.com/ulid/spec)

  Systems that do not involve legacy UUIDv1 SHOULD consider using UUIDv7 instead.
  """
  @spec uuid6() :: formatted
  @spec uuid6(format) :: formatted
  def uuid6(format \\ :default) when format in @formats do
    {time, clock} = Uniq.Generator.next()
    node = :crypto.strong_rand_bytes(6)

    # Deconstruct timestamp
    <<thi::48, tlo::12>> = <<time::biguint(60)>>

    # Encode the version to the most significant bits of the last octet of the timestamp
    tlo_and_version = <<6::4, tlo::12>>

    # Encode the variant in the most significant bits of the clock sequence
    clock_seq = <<@rfc_variant, clock::biguint(14)>>

    raw = <<thi::48, tlo_and_version::bits(16), clock_seq::bits(16), node::bits(48)>>

    format(raw, format)
  end

  @doc """
  Generates a UUID using the proposed version 7 scheme, found
  [here](https://datatracker.ietf.org/doc/html/draft-peabody-dispatch-new-uuid-format-04#section-5.2).
  This is a draft extension of RFC 4122, but has not yet been formally accepted.

  UUID version 7 features a time-ordered value field derived from the widely implemented and well
  known Unix Epoch timestamp source, the number of milliseconds seconds since midnight 1 Jan 1970
  UTC, leap seconds excluded. As well as improved entropy characteristics over versions 1 or 6.

  Implementations SHOULD utilize UUID version 7 over UUID version 1 and 6 if possible.
  """
  @spec uuid7() :: formatted
  @spec uuid7(format) :: formatted
  def uuid7(format \\ :default) when format in @formats do
    time = System.system_time(:millisecond)
    <<rand_a::12, _::6, rand_b::62>> = :crypto.strong_rand_bytes(10)

    raw = <<time::biguint(48), 7::4, rand_a::12, @rfc_variant, rand_b::62>>

    format(raw, format)
  end

  defp namespaced_uuid(version, algorithm, namespace, name, format) do
    id = namespace_id(namespace)

    <<tlo_mid::48, _::4, thi::12, _::2, rest::62>> = hash(algorithm, id <> name)

    raw = <<tlo_mid::48, version::4, thi::12, @rfc_variant, rest::62>>

    format(raw, format)
  end

  @doc """
  Like `info/1`, but raises if the input UUID is invalid.
  """
  @spec info!(binary, :struct) :: info | no_return
  @spec info!(binary, :keyword) :: Keyword.t() | no_return
  def info!(bin, style \\ :struct)

  def info!(bin, style) when is_binary(bin) do
    with {:ok, info} <- info(bin, style) do
      info
    else
      {:error, reason} ->
        raise ArgumentError, message: "invalid uuid: #{inspect(reason)}"
    end
  end

  def info!(_, _) do
    raise ArgumentError, message: "invalid uuid: :invalid_format"
  end

  @doc """
  This function parses the given UUID, in any of the supported encodings/formats, and produces
  the information gleaned from the encoded data.

  Two styles of information are supported, depending on whether the function is called via
  the compatibility shim for `:elixir_uuid`, or directly. You may pass `:struct` or `:keyword`
  manually if you wish to express a preference for one style or the other.

  The `:struct` form is the UUID structure used internally by this library, and it contains all
  of the information needed to re-encode the UUID as binary.

  The `:keyword` form matches 1:1 the keyword list produced by `UUID.info/1` provided by the
  `:elixir_uuid` library, and it contains slightly less information, but is useful for compatibility
  with legacy code that operates on that structure.

  # Examples

      iex> Uniq.UUID.info("870df8e8-3107-4487-8316-81e089b8c2cf", :keyword)
      {:ok, [uuid: "870df8e8-3107-4487-8316-81e089b8c2cf",
       binary: <<135, 13, 248, 232, 49, 7, 68, 135, 131, 22, 129, 224, 137, 184, 194, 207>>,
       type: :default,
       version: 4,
       variant: :rfc4122]}

      iex> Uniq.UUID.info("870df8e8-3107-4487-8316-81e089b8c2cf")
      {:ok, %Uniq.UUID{
       format: :default,
       version: 4,
       variant: <<2::2>>,
       time: 326283406408022248,
       seq: 790,
       node: <<129, 224, 137, 184, 194, 207>>,
       bytes: <<135, 13, 248, 232, 49, 7, 68, 135, 131, 22, 129, 224, 137, 184, 194, 207>>,
      }}

  """
  @spec info(binary, :struct) :: {:ok, info} | {:error, term}
  @spec info(binary, :keyword) :: {:ok, Keyword.t()} | {:error, term}
  def info(bin, style \\ :struct)

  # Compatibility with :elixir_uuid's info
  def info(bin, :keyword) when is_binary(bin) do
    with {:ok, uuid} <- parse(bin) do
      {:ok,
       [
         uuid: uuid |> to_string() |> String.downcase(),
         binary: uuid.bytes,
         type: uuid.format,
         version: uuid.version,
         variant: format_variant(uuid.variant)
       ]}
    end
  end

  def info(bin, :struct) when is_binary(bin) do
    parse(bin)
  end

  def info(_, style) when style in [:keyword, :struct],
    do: {:error, :invalid_format}

  @doc """
  Returns true if the given string is a valid UUID.

  ## Options

  * `strict: boolean`, if true, requires strict RFC 4122 conformance,
  i.e. version 6 is considered invalid
  """
  @spec valid?(binary) :: boolean
  @spec valid?(binary, Keyword.t()) :: boolean
  def valid?(bin, opts \\ [])

  def valid?(bin, opts) do
    strict? = Keyword.get(opts, :strict, false)

    case parse(bin) do
      {:ok, %__MODULE__{version: 6}} when strict? ->
        false

      {:ok, _} ->
        true

      {:error, _} ->
        false
    end
  end

  @doc """
  Parses a `#{__MODULE__}` from a binary.

  Supported formats include human-readable strings, as well as
  the raw binary form of the UUID.

  ## Examples

      iex> {:ok, uuid} = Uniq.UUID.parse("f81d4fae-7dec-11d0-a765-00a0c91e6bf6")
      {:ok, %Uniq.UUID{
        bytes: <<248, 29, 79, 174, 125, 236, 17, 208, 167, 101, 0, 160, 201, 30, 107, 246>>,
        format: :default,
        node: <<0, 160, 201, 30, 107, 246>>,
        seq: 10085,
        time: 130742845922168750,
        variant: <<2::size(2)>>,
        version: 1
      }}
      ...> {:ok, %Uniq.UUID{uuid | format: :urn}} == Uniq.UUID.parse("urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6")
      true

      iex> match?({:ok, %Uniq.UUID{format: :default, version: 1}}, Uniq.UUID.uuid1() |> Uniq.UUID.parse())
      true
  """
  @spec parse(binary) :: {:ok, info} | {:error, term}
  def parse(bin)

  def parse("urn:uuid:" <> uuid) do
    with {:ok, uuid} <- parse(uuid) do
      {:ok, %{uuid | format: :urn}}
    end
  end

  def parse(<<_::128>> = bin),
    do: parse_raw(bin, %__MODULE__{format: :raw})

  def parse(<<bin::bytes(32)>>) do
    bin
    |> decode_hex()
    |> parse_raw(%__MODULE__{format: :hex})
  rescue
    ArgumentError ->
      {:error, {:invalid_format, :hex}}
  end

  def parse(<<a::bytes(8), ?-, b::bytes(4), ?-, c::bytes(4), ?-, d::bytes(4), ?-, e::bytes(12)>>) do
    with {:ok, bin} <- Base.decode16(a <> b <> c <> d <> e, case: :mixed) do
      parse_raw(bin, %__MODULE__{format: :default})
    else
      :error ->
        {:error, {:invalid_format, :default}}
    end
  end

  def parse(<<uuid::bytes(22)>>) do
    with {:ok, value} <- Base.url_decode64(uuid <> "==") do
      parse_raw(value, %__MODULE__{format: :slug})
    else
      _ ->
        {:error, {:invalid_format, :slug}}
    end
  end

  def parse(_bin), do: {:error, :invalid_format}

  # Parse version
  defp parse_raw(<<_::48, version::uint(4), _::bitstring>> = bin, %__MODULE__{} = acc) do
    case version do
      v when v in [1, 3, 4, 5, 6, 7] ->
        with {:ok, uuid} <- parse_raw(version, bin, acc) do
          {:ok, %{uuid | bytes: bin}}
        end

      _ when bin == @nil_id ->
        {:ok, %{acc | bytes: @nil_id}}

      _ ->
        {:error, {:unknown_version, version}}
    end
  end

  # Parse variant
  defp parse_raw(version, <<time::64, @reserved_ncs, rest::bits(63)>>, acc),
    do: parse_raw(version, @reserved_ncs, time, rest, acc)

  defp parse_raw(version, <<time::64, @rfc_variant, rest::bits(62)>>, acc),
    do: parse_raw(version, @rfc_variant, time, rest, acc)

  defp parse_raw(version, <<time::64, @reserved_ms, rest::bits(61)>>, acc),
    do: parse_raw(version, @reserved_ms, time, rest, acc)

  defp parse_raw(version, <<time::64, @reserved_future, rest::bits(61)>>, acc),
    do: parse_raw(version, @reserved_future, time, rest, acc)

  defp parse_raw(_version, <<_time::64, variant::bits(3), _rest::bits(61)>>, _acc) do
    {:error, {:unknown_variant, variant}}
  end

  for variant <- [@reserved_ncs, @rfc_variant, @reserved_ms, @reserved_future] do
    variant_size = bit_size(variant)
    variant = Macro.escape(variant)

    # Parses RFC 4122, version 1-5 uuids
    defp parse_raw(version, unquote(variant), time, rest, %__MODULE__{} = acc) when version < 6 do
      variant_size = unquote(variant_size)
      clock_hi_size = 8 - variant_size
      clock_size = 8 + clock_hi_size

      with <<time_lo::bits(32), time_mid::bits(16), _version::4, time_hi::bits(12)>> <-
             <<time::64>>,
           <<timestamp::uint(60)>> <-
             <<time_hi::bits(12), time_mid::bits(16), time_lo::bits(32)>>,
           <<clock_hi::bits(clock_hi_size), clock_lo::bits(8), node::bits(48)>> <-
             rest,
           <<clock::uint(clock_size)>> <-
             <<clock_hi::bits(clock_hi_size), clock_lo::bits(8)>> do
        {:ok,
         %{
           acc
           | version: version,
             variant: unquote(variant),
             time: timestamp,
             seq: clock,
             node: node
         }}
      else
        other ->
          {:error, {:invalid_format, other, variant_size, clock_hi_size, clock_size}}
      end
    end
  end

  # Parses proposed version 7 uuids
  defp parse_raw(7, <<1::1, 0::1>> = variant, time, rest, %__MODULE__{} = acc) do
    with <<time::biguint(48), _version::4, _rand_a::12>> <- <<time::64>>,
         <<_rand_b::62>> <- rest do
      {:ok,
       %{
         acc
         | version: 7,
           variant: variant,
           time: time
       }}
    else
      _ ->
        {:error, {:invalid_format, :v7}}
    end
  end

  # Parses proposed version 6 uuids, which are very much like version 1, but with some field ordering changes
  defp parse_raw(6, <<1::1, 0::1>> = variant, time, rest, %__MODULE__{} = acc) do
    with <<time_hi::48, _version::4, time_lo::12>> <- <<time::64>>,
         <<timestamp::uint(60)>> <- <<time_hi::48, time_lo::12>>,
         <<clock::uint(14), node::bits(48)>> <-
           rest do
      {:ok,
       %{
         acc
         | version: 6,
           variant: variant,
           time: timestamp,
           seq: clock,
           node: node
       }}
    else
      _ ->
        {:error, {:invalid_format, :v6}}
    end
  end

  defp parse_raw(6, variant, _time, _rest, _acc), do: {:error, {:invalid_variant, variant}}

  # Handles proposed version 7 and 8 uuids
  defp parse_raw(version, _variant, _time, _rest, _acc),
    do: {:error, {:unsupported_version, version}}

  @doc """
  Formats a `#{__MODULE__}` as a string, using the format it was originally generated with.

  See `to_string/2` if you want to specify what format to produce.
  """
  @spec to_string(formatted | info) :: String.t()
  def to_string(uuid)

  def to_string(<<raw::bits(128)>>),
    do: format(raw, :default)

  def to_string(uuid) when is_binary(uuid) do
    uuid
    |> string_to_binary!()
    |> format(:default)
  end

  def to_string(%__MODULE__{bytes: raw, format: format}),
    do: format(raw, format)

  @doc """
  Same as `to_string/1`, except you can specify the desired format.

  The `format` can be one of the following:

  * `:default`, produces strings like `"f81d4fae-7dec-11d0-a765-00a0c91e6bf6"`
  * `:urn`, produces strings like `"urn:uuid:f81d4fae-7dec-11d0-a765-00a0c91e6bf6"`
  * `:hex`, produces strings like `"f81d4fae7dec11d0a76500a0c91e6bf6"`
  * `:slug`, produces strings like `"-B1Prn3sEdCnZQCgyR5r9g=="`
  * `:raw`, produces the raw binary encoding of the uuid in 128 bits
  """
  @spec to_string(formatted | info, format) :: String.t()
  def to_string(uuid, format)

  def to_string(<<raw::bits(128)>>, format) when format in @formats,
    do: format(raw, format)

  def to_string(uuid, format) when is_binary(uuid) and format in @formats do
    uuid
    |> string_to_binary!()
    |> format(format)
  end

  def to_string(%__MODULE__{bytes: raw}, format) when format in @formats,
    do: format(raw, format)

  @doc """
  This function takes a UUID string in any of the formats supported by `to_string/1`,
  and returns the raw, binary-encoded form.
  """
  @spec string_to_binary!(String.t()) :: t | no_return
  def string_to_binary!(str)

  def string_to_binary!(<<_::128>> = uuid), do: uuid

  def string_to_binary!(<<hex::bytes(32)>>) do
    decode_hex(hex)
  end

  def string_to_binary!(
        <<a::bytes(8), ?-, b::bytes(4), ?-, c::bytes(4), ?-, d::bytes(4), ?-, e::bytes(12)>>
      ) do
    decode_hex(a <> b <> c <> d <> e)
  end

  def string_to_binary!(<<slug::bytes(22)>>) do
    with {:ok, value} <- Base.url_decode64(slug <> "==") do
      value
    else
      _ ->
        raise ArgumentError, message: "invalid uuid string"
    end
  end

  def string_to_binary!(_) do
    raise ArgumentError, message: "invalid uuid string"
  end

  @doc """
  Compares two UUIDs, using their canonical 128-bit integer form, as described in RFC 4122.

  You may provide the UUIDs in either string, binary, or as a `Uniq.UUID` struct.
  """
  @spec compare(String.t() | info, String.t() | info) :: :lt | :eq | :gt
  def compare(a, b)

  def compare(%__MODULE__{} = a, %__MODULE__{} = b) do
    a = to_canonical_integer(a)
    b = to_canonical_integer(b)

    do_compare(a, b)
  end

  def compare(%__MODULE__{} = a, <<b::biguint(128)>>) do
    a = to_canonical_integer(a)

    do_compare(a, b)
  end

  def compare(%__MODULE__{} = a, b) when is_binary(b) do
    a = to_canonical_integer(a)
    b = string_to_binary!(b)

    do_compare(a, b)
  end

  def compare(<<a::biguint(128)>>, %__MODULE__{} = b) do
    b = to_canonical_integer(b)

    do_compare(a, b)
  end

  def compare(a, %__MODULE__{} = b) when is_binary(a) do
    a = string_to_binary!(a)
    b = to_canonical_integer(b)

    do_compare(a, b)
  end

  def compare(<<a::biguint(128)>>, <<b::biguint(128)>>),
    do: do_compare(a, b)

  def compare(a, b) when is_binary(a) and is_binary(b) do
    a = to_string(a)
    b = to_string(b)

    do_compare(a, b)
  end

  defp do_compare(a, b) do
    cond do
      a < b ->
        :lt

      a == b ->
        :eq

      :else ->
        :gt
    end
  end

  defp to_canonical_integer(%__MODULE__{bytes: <<value::biguint(128)>>}) do
    value
  end

  @doc false
  def format(raw, format)

  def format(raw, :raw), do: raw
  def format(raw, :default), do: format_default(raw)
  def format(raw, :hex), do: encode_hex(raw)
  def format(raw, :urn), do: "urn:uuid:#{format(raw, :default)}"
  def format(raw, :slug), do: Base.url_encode64(raw, padding: false)

  @compile {:inline, [format_default: 1]}

  defp format_default(<<
         a1::4,
         a2::4,
         a3::4,
         a4::4,
         a5::4,
         a6::4,
         a7::4,
         a8::4,
         b1::4,
         b2::4,
         b3::4,
         b4::4,
         c1::4,
         c2::4,
         c3::4,
         c4::4,
         d1::4,
         d2::4,
         d3::4,
         d4::4,
         e1::4,
         e2::4,
         e3::4,
         e4::4,
         e5::4,
         e6::4,
         e7::4,
         e8::4,
         e9::4,
         e10::4,
         e11::4,
         e12::4
       >>) do
    <<e(a1), e(a2), e(a3), e(a4), e(a5), e(a6), e(a7), e(a8), ?-, e(b1), e(b2), e(b3), e(b4), ?-,
      e(c1), e(c2), e(c3), e(c4), ?-, e(d1), e(d2), e(d3), e(d4), ?-, e(e1), e(e2), e(e3), e(e4),
      e(e5), e(e6), e(e7), e(e8), e(e9), e(e10), e(e11), e(e12)>>
  end

  @doc false

  defp format_variant(@reserved_future), do: :reserved_future
  defp format_variant(@reserved_ms), do: :reserved_microsoft
  defp format_variant(@rfc_variant), do: :rfc4122
  defp format_variant(@reserved_ncs), do: :reserved_ncs
  defp format_variant(_), do: :unknown

  defp mac_address do
    candidate_interface? = fn {_if, info} ->
      flags = Keyword.get(info, :flags, [])

      Enum.member?(flags, :up) and Enum.member?(flags, :broadcast) and
        Keyword.has_key?(info, :hwaddr)
    end

    with {:ok, interfaces} <- :inet.getifaddrs(),
         {_if, info} <- Enum.find(interfaces, candidate_interface?) do
      IO.iodata_to_binary(info[:hwaddr])
    else
      _ -> random_mac_address()
    end
  end

  def random_mac_address do
    # In lieu of a MAC address, we can generate an equivalent number of random bytes
    <<head::7, _::1, tail::40>> = :crypto.strong_rand_bytes(6)
    # Ensure the multicast bit is set, as per RFC 4122
    <<head::7, 1::1, tail::40>>
  end

  defp hash(:md5, data), do: :crypto.hash(:md5, data)
  defp hash(:sha, data), do: :binary.part(:crypto.hash(:sha, data), 0, 16)

  defp namespace_id(:dns), do: @dns_namespace_id
  defp namespace_id(:url), do: @url_namespace_id
  defp namespace_id(:oid), do: @oid_namespace_id
  defp namespace_id(:x500), do: @x500_namespace_id
  defp namespace_id(nil), do: @nil_id

  defp namespace_id(<<_::128>> = ns), do: ns

  defp namespace_id(<<ns::bytes(32)>>) do
    with {:ok, raw} <- Base.decode16(ns, case: :mixed) do
      raw
    else
      _ ->
        invalid_namespace!()
    end
  end

  defp namespace_id(
         <<a::bytes(8), ?-, b::bytes(4), ?-, c::bytes(4), ?-, d::bytes(4), ?-, e::bytes(12)>>
       ) do
    with {:ok, raw} <- Base.decode16(a <> b <> c <> d <> e, case: :mixed) do
      raw
    else
      _ ->
        invalid_namespace!()
    end
  end

  defp namespace_id(<<ns::bytes(22)>>) do
    with {:ok, raw} <- Base.url_decode64(ns <> "==") do
      raw
    else
      _ ->
        invalid_namespace!()
    end
  end

  defp namespace_id(_ns), do: invalid_namespace!()

  defp invalid_namespace!,
    do:
      raise(ArgumentError,
        message: "expected a valid namespace atom (:dns, :url, :oid, :x500), or a UUID string"
      )

  import Uniq.Macros, only: [defextension: 2, defshim: 3]

  @compile {:inline, [encode_hex: 1, decode_hex: 1]}

  defshim encode_hex(bin), to: :binary do
    defp encode_hex(bin), do: IO.iodata_to_binary(for <<bs::4 <- bin>>, do: e(bs))
  end

  defshim decode_hex(bin), to: :binary do
    defp decode_hex(
           <<a1, a2, a3, a4, a5, a6, a7, a8, b1, b2, b3, b4, c1, c2, c3, c4, d1, d2, d3, d4, e1,
             e2, e3, e4, e5, e6, e7, e8, e9, e10, e11, e12>>
         ) do
      <<d(a1)::4, d(a2)::4, d(a3)::4, d(a4)::4, d(a5)::4, d(a6)::4, d(a7)::4, d(a8)::4, d(b1)::4,
        d(b2)::4, d(b3)::4, d(b4)::4, d(c1)::4, d(c2)::4, d(c3)::4, d(c4)::4, d(d1)::4, d(d2)::4,
        d(d3)::4, d(d4)::4, d(e1)::4, d(e2)::4, d(e3)::4, d(e4)::4, d(e5)::4, d(e6)::4, d(e7)::4,
        d(e8)::4, d(e9)::4, d(e10)::4, d(e11)::4, d(e12)::4>>
    catch
      :throw, char ->
        raise ArgumentError, message: "#{inspect(<<char::utf8>>)} is not valid hex"
    end

    @compile {:inline, d: 1}

    defp d(?0), do: 0
    defp d(?1), do: 1
    defp d(?2), do: 2
    defp d(?3), do: 3
    defp d(?4), do: 4
    defp d(?5), do: 5
    defp d(?6), do: 6
    defp d(?7), do: 7
    defp d(?8), do: 8
    defp d(?9), do: 9
    defp d(?A), do: 10
    defp d(?B), do: 11
    defp d(?C), do: 12
    defp d(?D), do: 13
    defp d(?E), do: 14
    defp d(?F), do: 15
    defp d(?a), do: 10
    defp d(?b), do: 11
    defp d(?c), do: 12
    defp d(?d), do: 13
    defp d(?e), do: 14
    defp d(?f), do: 15
    defp d(char), do: throw(char)
  end

  @compile {:inline, e: 1}

  defp e(0), do: ?0
  defp e(1), do: ?1
  defp e(2), do: ?2
  defp e(3), do: ?3
  defp e(4), do: ?4
  defp e(5), do: ?5
  defp e(6), do: ?6
  defp e(7), do: ?7
  defp e(8), do: ?8
  defp e(9), do: ?9
  defp e(10), do: ?a
  defp e(11), do: ?b
  defp e(12), do: ?c
  defp e(13), do: ?d
  defp e(14), do: ?e
  defp e(15), do: ?f

  ## Ecto

  defextension Ecto.ParameterizedType do
    use Ecto.ParameterizedType

    @doc false
    @impl Ecto.ParameterizedType
    def init(opts) do
      schema = Keyword.fetch!(opts, :schema)
      field = Keyword.fetch!(opts, :field)
      format = Keyword.get(opts, :format, :default)
      dump = Keyword.get(opts, :dump, :raw)
      type = Keyword.get(opts, :type)

      unless format in @formats do
        raise ArgumentError,
          message:
            "invalid :format option, expected one of #{Enum.join(@formats, ",")}; got #{inspect(format)}"
      end

      unless dump in @formats do
        raise ArgumentError,
          message:
            "invalid :dump option, expected one of #{Enum.join(@formats, ",")}; got #{inspect(format)}"
      end

      version = Keyword.get(opts, :version, 4)

      unless version in [1, 3, 4, 5, 6, 7] do
        raise ArgumentError,
          message:
            "invalid uuid version, expected one of 1, 3, 4, 5, 6, or 7; got #{inspect(version)}"
      end

      namespace = Keyword.get(opts, :namespace)

      case namespace do
        nil when version in [3, 5] ->
          raise ArgumentError,
            message: "you must set :namespace to a valid uuid when :version is 3 or 5"

        nil ->
          :ok

        ns when ns in [:dns, :url, :oid, :x500] ->
          raise ArgumentError,
            message:
              "you must set :namespace to a uuid, the predefined namespaces are not permitted here"

        ns when is_binary(ns) ->
          :ok

        ns ->
          raise ArgumentError,
            message: "expected :namespace to be a binary, but got #{inspect(ns)}"
      end

      %{
        schema: schema,
        field: field,
        format: format,
        dump: dump,
        type: type,
        version: version,
        namespace: namespace
      }
    end

    @doc false
    @impl Ecto.ParameterizedType
    def type(%{type: nil, dump: :raw}), do: :binary
    def type(%{type: nil}), do: :string
    def type(%{type: t}), do: t

    # This is provided as a helper for autogenerating version 3 or 5 uuids
    @doc false
    @impl Ecto.ParameterizedType
    def autogenerate(%{format: format, version: version, namespace: namespace}) do
      case version do
        1 ->
          uuid1(format)

        4 ->
          uuid4(format)

        6 ->
          uuid6(format)

        7 ->
          uuid7(format)

        v when v in [3, 5] ->
          # 64 bits of entropy should be more than sufficient, since the total entropy
          # of the input here is 192 bits, which we get from the namespace (128 bits) + the name (64 bits).
          # That is then represented using only 128 bits (an entire MD5 hash, or 128 of the
          # 160 bits of a SHA1 hash). In short, its doubtful that using more than 8 bytes
          # of random data is going to have any appreciable benefit on uniqueness. Discounting
          # the namespace, the total entropy is only 64 bits, which in practice is constrained
          # by the hash itself, which is then further constrained by the fact that 6 bits of the
          # UUID are reserved for version and variant information. In short, even though we are
          # assuming a namespace that can contain 2^64 unique values, in practice it is less than
          # that, though it still leaves room for an astronomical number of unique identifiers.
          name = :crypto.strong_rand_bytes(8)

          case v do
            3 -> uuid3(namespace, name, format)
            5 -> uuid5(namespace, name, format)
          end
      end
    end

    @doc false
    @impl Ecto.ParameterizedType
    def cast(data, params)

    def cast(uuid, %{format: format}) when is_binary(uuid) do
      {:ok, to_string(uuid, format)}
    rescue
      ArgumentError ->
        :error
    end

    def cast(%__MODULE__{} = uuid, %{format: format}),
      do: {:ok, to_string(uuid, format)}

    def cast(nil, _params), do: {:ok, nil}

    def cast(_, _params), do: :error

    @doc false
    @impl Ecto.ParameterizedType
    def load(value, loader, params)

    def load(uuid, _loader, %{format: format}) when is_binary(uuid) do
      {:ok, to_string(uuid, format)}
    rescue
      ArgumentError ->
        :error
    end

    def load(nil, _loader, _params),
      do: {:ok, nil}

    @doc false
    @impl Ecto.ParameterizedType
    def dump(value, dumper, params)

    def dump(%__MODULE__{} = uuid, _dumper, %{dump: format}),
      do: {:ok, to_string(uuid, format)}

    def dump(uuid, _dumper, %{dump: format}) when is_binary(uuid) do
      {:ok, to_string(uuid, format)}
    rescue
      ArgumentError ->
        :error
    end

    def dump(nil, _dumper, _params),
      do: {:ok, nil}

    @doc false
    @impl Ecto.ParameterizedType
    def embed_as(_format, _params), do: :self

    @doc false
    @impl Ecto.ParameterizedType
    def equal?(a, b, params)

    def equal?(nil, nil, _), do: true
    def equal?(nil, b, _), do: to_string(b, :raw) == @nil_id
    def equal?(a, nil, _), do: to_string(a, :raw) == @nil_id
    def equal?(a, b, _), do: compare(to_string(a), to_string(b)) == :eq
  end

  defimpl String.Chars do
    alias Uniq.UUID

    def to_string(uuid), do: UUID.to_string(uuid)
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(%Uniq.UUID{bytes: bytes, version: version}, opts) do
      # Allow overriding the format in which UUIDs are displayed via custom inspect options
      format = Keyword.get(opts.custom_options, :format, :default)
      uuid = Uniq.UUID.to_string(bytes, format)

      concat(["#UUIDv", Kernel.to_string(version), "<", uuid, ">"])
    end
  end
end
