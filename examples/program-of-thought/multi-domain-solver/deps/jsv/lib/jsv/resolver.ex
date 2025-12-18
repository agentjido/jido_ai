defmodule JSV.Resolver do
  alias JSV.Helpers.EnumExt
  alias JSV.Key
  alias JSV.Ref
  alias JSV.RNS

  @moduledoc """
  A behaviour describing the implementation of a [guides/build/custom resolver.
  Resolves remote resources when building a JSON schema.
  """

  defmodule Resolved do
    @moduledoc """
    Metadata gathered from a remote schema or a sub-schema.
    """

    # TODO(Draft7-removal) drop parent_ns once we do not support draft-7
    @enforce_keys [:raw, :meta, :vocabularies, :ns, :parent_ns, :rev_path]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            raw: JSV.normal_schema(),
            meta: binary,
            vocabularies: term,
            ns: binary,
            parent_ns: binary
          }
  end

  defmodule Descriptor do
    @enforce_keys [:raw, :meta, :aliases, :ns, :parent_ns, :rev_path]
    defstruct @enforce_keys
    @moduledoc false
  end

  @doc """
  Receives an URI and the options passed in the resolver tuple to `JSV.build/2`
  and returns a result tuple for a raw JSON schema map.

  Returning boolean schemas from resolvers is not supported. You may wrap the
  boolean value in a `$defs` or any other pointer as a workaround.

  Schemas will be normalized using `JSV.Schema.normalize/1`. If the resolver
  returns schema that are already in JSON-decoded form (like a response body
  from an HTTP call) without atoms, module names or structs, the resolver
  implementation can return `{:normal, map}` instead to skip the normalization.
  """
  @callback resolve(uri :: String.t(), opts :: term) :: {:ok, map} | {:normal, map} | {:error, term}

  @derive {Inspect, Application.compile_env(:jsv, :resolver_inspect_derive, except: [:fetch_cache])}
  defstruct chain: [],
            default_meta: nil,
            # fetch_cache is a local cache for the resolver instance. Actual
            # caching of remote resources should be done in each resolver
            # implementation.
            fetch_cache: %{},
            resolved: %{}

  @opaque t :: %__MODULE__{}
  @type resolvable :: Key.ns() | Key.pointer() | Ref.t()

  @doc """
  Returns a new resolver, with the given behaviour implementations, and a
  default meta-schema URL to use with schemas that do not declare a `$schema`
  property.
  """
  @spec chain_of([{module, term}], binary) :: t
  def chain_of([_ | _] = resolvers, default_meta) do
    %__MODULE__{chain: resolvers, default_meta: default_meta}
  end

  @doc false
  @spec put_cached(t, binary | :root, JSV.normal_schema()) :: {:ok, t} | {:error, {:key_exists, term}}
  def put_cached(%__MODULE__{} = rsv, ext_id, raw_schema)
      when is_map(raw_schema) and (is_binary(ext_id) or :root == ext_id) do
    case rsv.fetch_cache do
      %{^ext_id => _} -> {:error, {:key_exists, ext_id}}
      fetch_cache -> {:ok, %{rsv | fetch_cache: Map.put(fetch_cache, ext_id, raw_schema)}}
    end
  end

  @doc """
  Fetches the remote resource into the internal resolver cache and returns a new
  resolver with that updated cache.
  """
  @spec resolve(t, resolvable) :: {:ok, t} | {:error, term}
  def resolve(rsv, resolvable) do
    case check_resolved(rsv, resolvable) do
      :unresolved -> do_resolve(rsv, resolvable)
      :already_resolved -> {:ok, rsv}
    end
  end

  defp do_resolve(rsv, resolvable) do
    with {:ok, raw_schema, rsv} <- ensure_fetched(rsv, resolvable),
         {:ok, identified_schemas} <- scan_schema(raw_schema, external_id(resolvable), rsv.default_meta),
         {:ok, cache_entries} <- create_cache_entries(identified_schemas),
         {:ok, rsv} <- insert_cache_entries(rsv, cache_entries) do
      resolve_meta_loop(rsv, metas_of(cache_entries))
    else
      {:error, _} = err -> err
    end
  end

  defp external_id(:root) do
    :root
  end

  defp external_id(ns) when is_binary(ns) do
    ns
  end

  defp external_id(%Ref{ns: ns}) do
    ns
  end

  defp metas_of(cache_entries) do
    cache_entries
    |> Enum.flat_map(fn
      {_, {:alias_of, _}} -> []
      {_, %{meta: meta}} -> [meta]
    end)
    |> Enum.uniq()
  end

  defp resolve_meta_loop(rsv, []) do
    {:ok, rsv}
  end

  defp resolve_meta_loop(rsv, [nil | tail]) do
    resolve_meta_loop(rsv, tail)
  end

  defp resolve_meta_loop(rsv, [meta | tail]) when is_binary(meta) do
    with :unresolved <- check_resolved(rsv, {:meta, meta}),
         {:ok, raw_schema, rsv} <- ensure_fetched(rsv, meta),
         {:ok, cache_entry} <- create_meta_entry(raw_schema, meta),
         {:ok, rsv} <- insert_cache_entries(rsv, [{{:meta, meta}, cache_entry}]) do
      resolve_meta_loop(rsv, [cache_entry.meta | tail])
    else
      :already_resolved -> resolve_meta_loop(rsv, tail)
      {:error, _} = err -> err
    end
  end

  defp check_resolved(rsv, id) when is_binary(id) or :root == id do
    case rsv do
      %{resolved: %{^id => _}} -> :already_resolved
      _ -> :unresolved
    end
  end

  defp check_resolved(rsv, {:meta, id}) when is_binary(id) do
    case rsv do
      %{resolved: %{{:meta, ^id} => _}} -> :already_resolved
      _ -> :unresolved
    end
  end

  defp check_resolved(rsv, %Ref{ns: ns}) do
    check_resolved(rsv, ns)
  end

  # Extract all $ids and achors. We receive the top schema
  defp scan_schema(top_schema, external_id, default_meta) when not is_nil(external_id) do
    {id, anchor, dynamic_anchor} = extract_keys(top_schema)

    # For self references that target "#" or "#some/path" in the document, when
    # the document does not have an id, we will force it. This is for the root
    # document only.

    ns =
      case id do
        nil -> external_id
        _ -> id
      end

    nss = [id, external_id] |> Enum.reject(&is_nil/1) |> Enum.uniq()

    # Anchor needs to be resolved from the $id or the external ID (an URL) if
    # set.
    anchors =
      case anchor do
        nil -> []
        _ -> Enum.map(nss, &Key.for_anchor(&1, anchor))
      end

    dynamic_anchors =
      case dynamic_anchor do
        # a dynamic anchor is also adressable as a regular anchor for the given namespace
        nil -> []
        _ -> Enum.flat_map(nss, &[Key.for_dynamic_anchor(&1, dynamic_anchor), Key.for_anchor(&1, dynamic_anchor)])
      end

    # The schema will be findable by its $id or external id.
    id_aliases = nss
    aliases = id_aliases ++ anchors ++ dynamic_anchors

    # If no metaschema is defined we will use the default draft as a fallback.
    # We normalize it because many schemas use
    # "http://json-schema.org/draft-07/schema#" with a trailing "#".
    meta = normalize_meta(Map.get(top_schema, "$schema", default_meta))

    top_descriptor = %Descriptor{
      raw: top_schema,
      meta: meta,
      aliases: aliases,
      ns: ns,
      parent_ns: nil,
      rev_path: [external_id]
    }

    acc = [top_descriptor]

    scan_map_values(top_schema, id, nss, meta, [ns], acc)
  end

  defp scan_subschema(raw_schema, ns, nss, meta, path, acc) when is_map(raw_schema) do
    # If the subschema defines an id, we will discard the current namespaces, as
    # the sibling or nested anchors will now only relate to this id

    parent_ns = ns

    {id, anchors, dynamic_anchor} =
      case extract_keys(raw_schema) do
        # ID that is only a fragment is replaced as an anchor
        {"#" <> frag_id, anchor, dynamic_anchor} -> {nil, [frag_id | List.wrap(anchor)], dynamic_anchor}
        {id, anchor, dynamic_anchor} -> {id, List.wrap(anchor), dynamic_anchor}
      end

    {id_aliases, ns, nss} =
      with true <- is_binary(id),
           {:ok, full_id} <- merge_id(ns, id) do
        {[full_id], full_id, [full_id]}
      else
        _ -> {[], ns, nss}
      end

    anchors =
      for new_ns <- nss, a <- anchors do
        Key.for_anchor(new_ns, a)
      end

    dynamic_anchors =
      case dynamic_anchor do
        nil -> []
        # a dynamic anchor is also adressable as a regular anchor for the given namespace
        da -> Enum.flat_map(nss, &[Key.for_dynamic_anchor(&1, da), Key.for_anchor(&1, da)])
      end

    # We do not check for the meta $schema is subschemas, we only add the
    # parent_one to the descriptor.

    acc =
      case(id_aliases ++ anchors ++ dynamic_anchors) do
        [] ->
          acc

        aliases ->
          descriptor =
            %Descriptor{
              raw: raw_schema,
              meta: meta,
              aliases: aliases,
              ns: ns,
              parent_ns: parent_ns,
              rev_path: path
            }

          [descriptor | acc]
      end

    scan_map_values(raw_schema, ns, nss, meta, path, acc)
  end

  defp scan_subschema(scalar, _parent_id, _nss, _meta, _path, acc)
       when is_binary(scalar)
       when is_atom(scalar)
       when is_number(scalar) do
    {:ok, acc}
  end

  defp scan_subschema(list, parent_id, nss, meta, path, acc) when is_list(list) do
    list
    |> Enum.with_index()
    |> EnumExt.reduce_ok(acc, fn {item, index}, acc ->
      scan_subschema(item, parent_id, nss, meta, [index | path], acc)
    end)
  end

  defp extract_keys(schema) do
    id =
      case Map.fetch(schema, "$id") do
        {:ok, id} -> id
        :error -> nil
      end

    anchor =
      case Map.fetch(schema, "$anchor") do
        {:ok, anchor} -> anchor
        :error -> nil
      end

    dynamic_anchor =
      case Map.fetch(schema, "$dynamicAnchor") do
        {:ok, dynamic_anchor} -> dynamic_anchor
        :error -> nil
      end

    {id, anchor, dynamic_anchor}
  end

  defp scan_map_values(schema, parent_id, nss, meta, path, acc) do
    EnumExt.reduce_ok(schema, acc, fn
      {"properties", props}, acc when is_map(props) ->
        scan_map_values(props, parent_id, nss, meta, ["properties" | path], acc)

      {"properties", props}, _ ->
        raise "invalid properties: #{inspect(props)}"

      {ignored, _}, _ when ignored in ["enum", "const"] ->
        {:ok, acc}

      {k, v}, acc ->
        scan_subschema(v, parent_id, nss, meta, [k | path], acc)
    end)
  end

  defp create_cache_entries(identified_schemas) do
    {:ok, Enum.flat_map(identified_schemas, &to_cache_entries/1)}
  end

  defp to_cache_entries(descriptor) do
    %Descriptor{aliases: aliases, meta: meta, raw: raw, ns: ns, parent_ns: parent_ns, rev_path: rev_path} = descriptor

    resolved =
      %Resolved{meta: meta, raw: raw, ns: ns, parent_ns: parent_ns, vocabularies: nil, rev_path: rev_path}

    case aliases do
      [single] -> [{single, resolved}]
      [first | aliases] -> [{first, resolved} | Enum.map(aliases, &{&1, {:alias_of, first}})]
    end
  end

  defp insert_cache_entries(rsv, entries) do
    %__MODULE__{resolved: cache} = rsv

    cache_result =
      EnumExt.reduce_ok(entries, cache, fn {k, resolved}, cache ->
        case cache do
          %{^k => existing} ->
            # Allow a duplicate resolution that is the exact same value as the
            # preexisting copy. This allows a root schema with an $id to reference
            # itself with an external id such as `jsv:module:MODULE`.
            check_duplicated_cache_entry(k, resolved, existing, cache)

          _ ->
            {:ok, Map.put(cache, k, resolved)}
        end
      end)

    with {:ok, cache} <- cache_result do
      {:ok, %{rsv | resolved: cache}}
    end
  end

  defp check_duplicated_cache_entry(k, resolved, existing, cache) do
    case {resolved, existing} do
      {%Resolved{raw: same}, %Resolved{raw: same}} -> {:ok, cache}
      _ -> {:error, {:duplicate_resolution, k}}
    end
  end

  defp create_meta_entry(raw_schema, ext_id) when not is_struct(raw_schema) do
    case fetch_vocabulary_from_raw(raw_schema, ext_id) do
      {:ok, vocabulary} ->
        # Meta entries are only identified by they external URL so the :ns and
        # :raw value should not be used anywhere. We will just put :__meta__ in
        # here so it's easier to debug.
        resolved = %Resolved{
          vocabularies: vocabulary,
          meta: nil,
          ns: :__meta__,
          parent_ns: nil,
          raw: :__meta__,
          rev_path: [ext_id]
        }

        {:ok, resolved}

      :error ->
        {:error, {:undefined_vocabulary, ext_id}}
    end
  end

  defp fetch_vocabulary_from_raw(raw_schema, ext_id) do
    case Map.fetch(raw_schema, "$vocabulary") do
      {:ok, vocab} when is_map(vocab) -> {:ok, vocab}
      :error -> vocabulary_fallback(ext_id)
    end
  end

  defp vocabulary_fallback("http://json-schema.org/draft-07/schema") do
    vocab = %{
      "https://json-schema.org/draft-07/--fallback--vocab/core" => true,
      "https://json-schema.org/draft-07/--fallback--vocab/validation" => true,
      "https://json-schema.org/draft-07/--fallback--vocab/applicator" => true,
      "https://json-schema.org/draft-07/--fallback--vocab/content" => true,
      "https://json-schema.org/draft-07/--fallback--vocab/format-annotation" => true,
      "https://json-schema.org/draft-07/--fallback--vocab/meta-data" => true

      # We do not declare format assertion to have the same behaviour as 2020-12
      # "https://json-schema.org/draft-07/--fallback--vocab/format-assertion" => true,
    }

    {:ok, vocab}
  end

  defp vocabulary_fallback(_) do
    :error
  end

  defp ensure_fetched(rsv, fetchable) do
    with :unfetched <- check_fetched(rsv, fetchable),
         {:ok, ext_id, raw_schema} <- fetch_raw_schema(rsv, fetchable),
         {:ok, rsv} <- put_cached(rsv, ext_id, raw_schema) do
      {:ok, raw_schema, rsv}
    else
      {:already_fetched, raw_schema} -> {:ok, raw_schema, rsv}
      {:error, _} = err -> err
    end
  end

  defp check_fetched(rsv, %Ref{ns: ns}) do
    check_fetched(rsv, ns)
  end

  defp check_fetched(rsv, id) when is_binary(id) when :root == id do
    case rsv do
      %{fetch_cache: %{^id => fetched}} -> {:already_fetched, fetched}
      _ -> :unfetched
    end
  end

  @spec fetch_raw_schema(t, binary | {:meta, binary} | Ref.t()) :: {:ok, binary, JSV.normal_schema()} | {:error, term}
  defp fetch_raw_schema(rsv, {:meta, url}) do
    fetch_raw_schema(rsv, url)
  end

  defp fetch_raw_schema(rsv, url) when is_binary(url) do
    call_chain(rsv.chain, url)
  end

  defp fetch_raw_schema(rsv, %Ref{ns: ns}) do
    fetch_raw_schema(rsv, ns)
  end

  defp call_chain(chain, url) do
    call_chain(chain, url, _err_acc = [])
  end

  defp call_chain([{module, opts} | chain], url, err_acc) do
    case module.resolve(url, opts) do
      {:ok, resolved} when is_map(resolved) ->
        {:ok, url, normalize_resolved(resolved)}

      {:normal, resolved} when is_map(resolved) ->
        {:ok, url, resolved}

      {:error, reason} ->
        call_chain(chain, url, [{module, reason} | err_acc])

      other ->
        raise "invalid return from #{inspect(module)}.resolve/2, expected {:ok, map} or {:error, reason}, got: #{inspect(other)}"
    end
  end

  defp call_chain([], _url, err_acc) do
    {:error, {:resolver_error, :lists.reverse(err_acc)}}
  end

  defp normalize_resolved(map) when is_map(map) do
    JSV.Schema.normalize(map)
  end

  defp merge_id(nil, child) do
    RNS.derive(child, "")
  end

  defp merge_id(parent, child) do
    RNS.derive(parent, child)
  end

  # Removes the fragment from the given URL. Accepts nil values
  defp normalize_meta(nil) do
    nil
  end

  defp normalize_meta(meta) do
    case URI.parse(meta) do
      %{fragment: nil} -> meta
      uri -> URI.to_string(%{uri | fragment: nil})
    end
  end

  @doc """
  Returns the $vocabulary property of a schema identified by its namespace.

  The schema must have been resolved previously as a meta-schema (_i.e._ found
  in an $schema property of a resolved schema).
  """
  @spec fetch_vocabulary(t, binary) :: {:ok, %{optional(binary) => boolean}} | {:error, term}
  def fetch_vocabulary(rsv, meta) do
    case fetch_resolved(rsv, {:meta, meta}) do
      {:ok, %Resolved{vocabularies: vocabularies}} -> {:ok, vocabularies}
      {:error, _} = err -> err
    end
  end

  @doc """
  Returns the raw schema identified by the given key if was previously resolved.
  """
  @spec fetch_resolved(t(), resolvable | {:meta, resolvable}) ::
          {:ok, Resolved.t() | {:alias_of, Key.t()}} | {:error, term}
  def fetch_resolved(rsv, {:pointer, _, _} = pointer) do
    fetch_pointer(rsv.resolved, pointer)
  end

  def fetch_resolved(rsv, key) do
    fetch_local(rsv.resolved, key)
  end

  defp fetch_pointer(cache, {:pointer, ns, docpath}) do
    with {:ok, %Resolved{raw: raw, meta: meta, ns: ns, parent_ns: parent_ns, rev_path: rev_path}} <-
           fetch_local(cache, ns, :dealias),
         {:ok, [sub | _] = parent_chain} <- fetch_docpath(raw, docpath),
         {:ok, ns, parent_ns} <- derive_docpath_ns(parent_chain, ns, parent_ns) do
      {:ok,
       %Resolved{
         raw: sub,
         meta: meta,
         vocabularies: nil,
         ns: ns,
         parent_ns: parent_ns,
         rev_path: :lists.reverse(docpath, rev_path)
       }}
    else
      {:error, _} = err -> err
    end
  end

  defp fetch_local(cache, key, aliases \\ nil) do
    case Map.fetch(cache, key) do
      {:ok, {:alias_of, key}} when aliases == :dealias -> fetch_local(cache, key)
      {:ok, {:alias_of, key}} -> {:ok, {:alias_of, key}}
      {:ok, cached} -> {:ok, cached}
      :error -> {:error, {:unresolved, key}}
    end
  end

  defp fetch_docpath(raw_schema, docpath) do
    case do_fetch_docpath(raw_schema, docpath, []) do
      {:ok, sub} -> {:ok, sub}
      {:error, reason} -> {:error, {:invalid_docpath, docpath, raw_schema, reason}}
    end
  end

  # When fetching a docpath we will create a list of all parents up to the
  # fetched subschema. The top parent is the last item in the list, the fetched
  # subschema is the head.
  #
  # TODO(Draft7-removal) This is to support Draft 7 to define the correct NS for
  # the subschema. We can remove that list building once Draft 7 is not
  # supported anymore.
  defp do_fetch_docpath(list, [h | t], parents) when is_list(list) and is_integer(h) do
    case Enum.fetch(list, h) do
      {:ok, item} -> do_fetch_docpath(item, t, [list | parents])
      :error -> {:error, {:pointer_error, h, list}}
    end
  end

  defp do_fetch_docpath(raw_schema, [h | t], parents) when is_map(raw_schema) and is_binary(h) do
    case Map.fetch(raw_schema, h) do
      {:ok, sub} -> do_fetch_docpath(sub, t, [raw_schema | parents])
      :error -> {:error, {:pointer_error, h, raw_schema}}
    end
  end

  defp do_fetch_docpath(raw_schema, [], parents) do
    {:ok, [raw_schema | parents]}
  end

  # TODO(Draft7-removal) remove derive_docpath_ns/3, this is only to support Draft7 where we
  # must keep the parent_ns around in a %Resolved{}
  defp derive_docpath_ns([%{"$id" => id} | [_ | _] = tail], parent_ns, parent_parent_ns) do
    # Recursion first to go back to the top schema of the docpath
    with {:ok, parent_ns, _parent_parent_ns} <- derive_docpath_ns(tail, parent_ns, parent_parent_ns),
         {:ok, new_ns} <- RNS.derive(parent_ns, id) do
      {:ok, new_ns, parent_ns}
    end
  end

  defp derive_docpath_ns([_sub_no_id | [_ | _] = tail], parent_ns, parent_parent_ns) do
    derive_docpath_ns(tail, parent_ns, parent_parent_ns)
  end

  defp derive_docpath_ns([_single], ns, parent_ns) do
    # Do not derive from the last schema in the list, as `ns, parent_ns` represent that schema itself
    {:ok, ns, parent_ns}
  end
end
