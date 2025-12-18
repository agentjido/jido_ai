defmodule JSV.Key do
  alias JSV.Ref

  @moduledoc """
  Helpers around the different key formats used in the resolver, builder and
  validator states to index sub schemas, referenced schemas, anchor or meta
  schemas.

  For instance:

  * We have a `{"$ref": "http://some-schema/#$defs/order"}` JSON schema.

  * The builder will build the `$ref` keyword as a key: `{:pointer,
    "http://some-schema/", ["$defs","order"]}`.

  * The builder, via the resolver, will fetch `http://some-schema/`, store it
    locally and build validators. Those validators will be stored under the same
    key (`{:pointer, "http://some-schema/", ["$defs","order"]}`) in the root
    schema.

  * When the validator will validate the reference, it will fetch that key from
    the root schema and apply the retrieved validators to the data.
  """

  @type pointer :: {:pointer, binary, [binary]}
  @type anchor :: {:anchor, binary, binary}
  @type dynamic_anchor :: {:dynamic_anchor, binary, binary}
  @type ns :: Ref.ns()
  @type t :: ns | anchor | dynamic_anchor | pointer

  @doc """
  Creates a new key from an external or local reference.
  """
  @spec of(ns | Ref.t()) :: t
  def of(namespace_or_ref)

  def of(binary) when is_binary(binary) do
    binary
  end

  def of(:root) do
    :root
  end

  def of(%Ref{} = ref) do
    of_ref(ref)
  end

  defp of_ref(%{dynamic?: true, ns: ns, kind: :anchor} = ref) do
    %{arg: arg} = ref
    for_dynamic_anchor(ns, arg)
  end

  defp of_ref(%{dynamic?: false} = ref) do
    %Ref{kind: kind, ns: ns, arg: arg} = ref

    case kind do
      :top -> ns
      :pointer -> for_pointer(ns, arg)
      :anchor -> for_anchor(ns, arg)
    end
  end

  @doc "Returns a pointer type key."
  @spec for_pointer(ns, [binary()]) :: pointer()
  def for_pointer(ns, arg) when is_list(arg) do
    {:pointer, ns, arg}
  end

  @doc "Returns an anchor type key."
  @spec for_anchor(ns, binary) :: anchor()
  def for_anchor(ns, arg) when is_binary(arg) do
    {:anchor, ns, arg}
  end

  @doc "Returns a dynamic anchor type key."
  @spec for_dynamic_anchor(ns, binary) :: dynamic_anchor()
  def for_dynamic_anchor(ns, arg) when is_binary(arg) do
    {:dynamic_anchor, ns, arg}
  end

  @doc "Returns the namespace of the key."
  @spec namespace_of(t) :: ns
  def namespace_of(binary) when is_binary(binary) do
    binary
  end

  def namespace_of(:root) do
    :root
  end

  def namespace_of({:anchor, ns, _}) do
    ns
  end

  def namespace_of({:dynamic_anchor, ns, _}) do
    ns
  end

  def namespace_of({:pointer, ns, _}) do
    ns
  end

  @doc """
  Returns a string representation of the key, in a URL/JSON pointer format,
  as chardata.
  """
  @spec to_iodata(t) :: IO.chardata()
  def to_iodata(bin) when is_binary(bin) do
    bin
  end

  def to_iodata(:root) do
    [""]
  end

  def to_iodata({:pointer, ns, [_ | _] = path}) do
    [ns_to_iodata(ns), "#/" | Enum.map_intersperse(path, "/", &to_iodata_segment/1)]
  end

  def to_iodata({:dynamic_anchor, ns, anchor}) do
    [ns_to_iodata(ns), "#/", anchor]
  end

  def to_iodata({:anchor, ns, anchor}) do
    [ns_to_iodata(ns), "#/", anchor]
  end

  defp ns_to_iodata(:root) do
    ""
  end

  defp ns_to_iodata(bin) when is_binary(bin) do
    bin
  end

  defp to_iodata_segment(bin) when is_binary(bin) do
    bin
  end

  defp to_iodata_segment(n) when is_integer(n) do
    Integer.to_string(n)
  end
end
