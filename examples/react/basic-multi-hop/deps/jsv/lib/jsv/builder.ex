defmodule JSV.Builder do
  alias JSV.BooleanSchema
  alias JSV.BuildError
  alias JSV.ErrorFormatter
  alias JSV.Key
  alias JSV.Ref
  alias JSV.Resolver
  alias JSV.Resolver.Resolved
  alias JSV.RNS
  alias JSV.Validator
  alias JSV.Vocabulary

  @moduledoc """
  Internal logic to build raw schemas into `JSV.Root` structs.
  """

  @derive {Inspect, Application.compile_env(:jsv, :builder_inspect_derive, only: [:ns, :current_rev_path, :resolver])}
  @enforce_keys [:resolver]
  defstruct resolver: nil,
            staged: [],
            vocabularies: nil,
            vocabulary_impls: %{},
            ns: nil,
            parent_ns: nil,
            opts: [],
            current_rev_path: []

  @type t :: %__MODULE__{resolver: term, staged: [term], vocabularies: term, ns: term, parent_ns: term, opts: term}
  @type resolvable :: Resolver.resolvable()
  @type buildable :: {:resolved, resolvable} | resolvable
  @type path_segment :: binary | non_neg_integer | atom | {atom, term}

  @doc false
  defmacro unwrap_ok(call) do
    if !Macro.Env.has_var?(__CALLER__, {:builder, nil}) do
      raise "unwrap_ok requires a `builder` variable to be defined in scope"
    end

    errcall = quoted_call_parts(call, __CALLER__.module)

    quote generated: true do
      case unquote(call) do
        {:ok, value} -> value
        {:error, reason} -> unquote(__MODULE__).fail(var!(builder), reason, unquote(errcall))
        :error -> unquote(__MODULE__).fail(var!(builder), :error, unquote(errcall))
      end
    end
  end

  defmacrop unwrap_ok_resolver(call) do
    errcall = quoted_call_parts(call, __CALLER__.module)

    quote generated: true do
      case unquote(call) do
        {:ok, value} -> value
        {:error, reason} -> unquote(__MODULE__).fail(var!(builder), reason, unquote(errcall))
        :error -> unquote(__MODULE__).fail(var!(builder), :error, unquote(errcall))
      end
    end
  end

  defp quoted_call_parts(call, module) do
    {m, f, a} =
      case Macro.decompose_call(call) do
        {m, f, a} -> {m, f, a}
        {f, a} -> {module, f, a}
      end

    quote do
      {unquote(m), unquote(f), unquote(a)}
    end
  end

  @doc """
  Returns a new builder. Builders are not reusable ; a fresh builder must be
  made for each different root schema.
  """
  @spec new(keyword) :: t
  def new(opts) do
    # beware, the :vocabularies option is not the final value of the
    # :vocabularies key in the Builder struct. It's a configuration option to
    # build the final value. This option is kept around in the :vocabulary_impls
    # struct key after being merged on top of the default implementations.
    {resolver, opts} = Keyword.pop!(opts, :resolver)
    {add_vocabulary_impls, opts} = Keyword.pop!(opts, :vocabularies)
    vocabulary_impls = build_vocabulary_impls(add_vocabulary_impls)

    struct!(__MODULE__, resolver: resolver, opts: opts, vocabulary_impls: vocabulary_impls)
  end

  @doc """
  Builds the given root schema or reference into the given validators.
  """
  @spec build!(t, Ref.ns() | Ref.t(), Validator.validators()) :: {Validator.validators(), t}
  def build!(builder, source, validators) do
    builder
    |> stage_build(source)
    |> build_all_staged(validators)
  end

  @doc """
  Adds a new key to be built later. A key is generatlly derived from a
  reference.
  """
  @spec stage_build(t, buildable) :: t()
  def stage_build(%__MODULE__{staged: staged} = builder, buildable) do
    %{builder | staged: append_unique(staged, buildable)}
  end

  @doc """
  Adds a schema under the given key to the build, so that key or references to
  this schema or its subschemas become buildable.
  """
  @spec add_schema!(t, Key.t(), JSV.normal_schema()) :: t
  def add_schema!(builder, key, schema) do
    rsv = unwrap_ok_resolver(Resolver.put_cached(builder.resolver, key, schema))
    %{builder | resolver: rsv}
  end

  defp append_unique([same | t], same) do
    [same | t]
  end

  defp append_unique([h | t], key) do
    [h | append_unique(t, key)]
  end

  defp append_unique([], key) do
    [key]
  end

  @doc """
  Ensures that the remote resource that the given reference or key points to is
  fetched in the builder internal cache
  """
  @spec ensure_resolved!(t, resolvable) :: t
  def ensure_resolved!(%__MODULE__{resolver: resolver} = builder, resolvable) do
    resolver = unwrap_ok_resolver(Resolver.resolve(resolver, resolvable))
    %{builder | resolver: resolver}
  end

  @doc """
  Returns the raw schema identified by the given key. Use `ensure_resolved/2`
  before if the resource may not have been fetched.
  """
  @spec fetch_resolved!(t, Key.t()) :: Resolved.t() | {:alias_of, Key.t()}
  def fetch_resolved!(%{resolver: resolver} = builder, key) do
    unwrap_ok_resolver(Resolver.fetch_resolved(resolver, key))
  end

  defp take_staged(%{staged: []}) do
    :empty
  end

  defp take_staged(%__MODULE__{staged: [staged | tail]} = builder) do
    {staged, %{builder | staged: tail}}
  end

  # * all_validators represent the map of schema_id_or_ref => validators for
  #   this schema
  # * schema validators is the validators corresponding to one schema document
  # * mod_validators are the created validators from part of a schema
  #   keywords+values and a vocabulary module

  defp build_all_staged(builder, all_validators) do
    # We split the buildables in three cases:
    # - One dynamic refs will lead to build all existing dynamic refs not
    #   already built.
    # - Resolvables such as ID and Ref will be resolved and turned into
    #   :resolved tuples. We do not build them right away to avoid building them
    #   multiple times.
    # - :resolved tuples assume to be already resolved and will be built into
    #   validators.
    #
    # We need to do that 2-pass in the stage list because some resolvables
    # (dynamic refs) lead to stage and build multiple validators.

    case take_staged(builder) do
      {{:resolved, vkey}, builder} ->
        case check_not_built(all_validators, vkey) do
          :buildable ->
            resolved = fetch_resolved!(builder, vkey)
            {schema_validators, builder} = build_resolved(builder, resolved)
            build_all_staged(builder, register_validator(all_validators, vkey, schema_validators))

          :already_built ->
            build_all_staged(builder, all_validators)
        end

      {%Ref{kind: :anchor, dynamic?: true, arg: anchor}, builder} ->
        builder = stage_dynamic_anchors(builder, anchor)
        build_all_staged(builder, all_validators)

      {resolvable, builder} when is_binary(resolvable) when is_struct(resolvable, Ref) when :root == resolvable ->
        case check_not_built(all_validators, Key.of(resolvable)) do
          :buildable ->
            builder = resolve_and_stage(builder, resolvable)
            build_all_staged(builder, all_validators)

          :already_built ->
            build_all_staged(builder, all_validators)
        end

      # Finally there is nothing more to build
      :empty ->
        {all_validators, builder}
    end
  end

  defp register_validator(all_validators, vkey, schema_validators) do
    Map.put(all_validators, vkey, schema_validators)
  end

  defp resolve_and_stage(builder, resolvable) do
    vkey = Key.of(resolvable)

    builder
    |> ensure_resolved!(resolvable)
    |> stage_build({:resolved, vkey})
  end

  defp stage_dynamic_anchors(%__MODULE__{} = builder, anchor) do
    # To build all dynamic references we tap into the resolver. The resolver
    # also conveniently allows to fetch by its own keys ({:dynamic_anchor,_,_})
    # instead of passing the original ref.
    #
    # Everytime we encounter a dynamic ref in build_all_staged/2 we need to
    # stage the build of all dynamic references with the given anchor.
    #
    # But if we insert the ref itself it will lead to an infinite loop, since we
    # do that when we find a ref in this loop.
    #
    # So instead of inserting the ref we insert the Key, and the Key module and
    # Resolver accept to work with that kind of schema identifier (that is,
    # {:dynamic_anchor, _, _} tuple).
    #
    # New items only come up when we build subschemas by staging a ref in the
    # builder.
    #
    # But to keep it clean we scan the whole list every time.
    dynamic_buildables =
      Enum.flat_map(builder.resolver.resolved, fn
        {{:dynamic_anchor, _, ^anchor} = vkey, _resolved} -> [{:resolved, vkey}]
        _ -> []
      end)

    %{builder | staged: dynamic_buildables ++ builder.staged}
  end

  defp check_not_built(all_validators, vkey) do
    case is_map_key(all_validators, vkey) do
      true -> :already_built
      false -> :buildable
    end
  end

  defp build_resolved(builder, {:alias_of, key}) do
    # Keep the alias in the validators but ensure the value it points to gets
    # built too by staging it.
    #
    # The alias returned by the resolver is a key, it is not a binary or a
    # %Ref{} staged by some vocabulary. (Thouh a binary is a valid key). So we
    # must stage it as already resolved.
    #
    # Since this key is provided by the resolver we have the guarantee that the
    # alias target is actually resolved already.
    {{:alias_of, key}, stage_build(builder, {:resolved, key})}
  end

  defp build_resolved(%__MODULE__{} = builder, resolved) do
    %Resolved{meta: meta, ns: ns, parent_ns: parent_ns, rev_path: rev_path} = resolved

    raw_vocabularies = fetch_vocabulary(builder, meta)
    vocabularies = load_vocabularies(builder, raw_vocabularies)

    builder = %{builder | vocabularies: vocabularies, ns: ns, parent_ns: parent_ns}
    # Here we call `do_build_sub` directly instead of `build_sub` because in
    # this case, if the sub schema has an $id we want to actually build it
    # and not register an alias.
    #
    # We set the current_rev_path on the builder because if the vocabulary
    # module recursively calls build_sub we will need the current path
    # later.

    with_current_path(builder, rev_path, fn builder ->
      do_build_sub(resolved.raw, rev_path, builder)
    end)
  end

  defp with_current_path(%__MODULE__{} = builder, rev_path, fun) do
    previous_rev_path = builder.current_rev_path

    next = %{builder | current_rev_path: rev_path}
    {value, %__MODULE__{} = new_builder} = fun.(next)
    {value, %{new_builder | current_rev_path: previous_rev_path}}
  end

  defp fetch_vocabulary(builder, meta) do
    unwrap_ok_resolver(Resolver.fetch_vocabulary(builder.resolver, meta))
  end

  @doc """
  Builds a subschema. Called from vocabulary modules to build nested schemas
  such as in properties, if/else, items, etc.
  """
  @spec build_sub!(JSV.normal_schema(), [path_segment()], t) :: {Validator.validator(), t} | {:error, term}
  def build_sub!(%{"$id" => id}, _add_rev_path, builder) do
    case RNS.derive(builder.ns, id) do
      {:ok, key} -> {{:alias_of, key}, stage_build(builder, key)}
      {:error, reason} -> fail(builder, reason, :deriving_namespace)
    end
  end

  def build_sub!(raw_schema, add_rev_path, builder) when is_map(raw_schema) when is_boolean(raw_schema) do
    new_rev_path = add_rev_path ++ builder.current_rev_path

    with_current_path(builder, new_rev_path, fn builder ->
      do_build_sub(raw_schema, new_rev_path, builder)
    end)
  end

  def build_sub!(other, add_rev_path, builder) do
    fail(
      builder,
      {:invalid_sub_schema, JSV.ErrorFormatter.format_schema_path(add_rev_path ++ builder.current_rev_path), other},
      :building_subschema
    )
  end

  defp do_build_sub(raw_schema, rev_path, builder) when is_map(raw_schema) do
    {_leftovers, schema_validators, builder} =
      Enum.reduce(builder.vocabularies, {raw_schema, [], builder}, fn module_or_tuple,
                                                                      {remaining_pairs, schema_validators, builder} ->
        # For one vocabulary module we reduce over the raw schema keywords to
        # accumulate the validator map.
        {module, init_opts} = mod_and_init_opts(module_or_tuple)

        {remaining_pairs, mod_validators, builder} =
          build_mod_validators(remaining_pairs, module, init_opts, builder, raw_schema)

        case mod_validators do
          :ignore -> {remaining_pairs, schema_validators, builder}
          _ -> {remaining_pairs, [{module, mod_validators} | schema_validators], builder}
        end
      end)

    # TODO we should warn if the dialect did not pick all elements from the
    # schema. But this should be opt-in. We should have an option that accepts a
    # fun, so an user of the library could raise, log, or pass.
    #
    #     case leftovers do
    #       [] -> :ok
    #       other -> IO.warn("got some leftovers: #{inspect(other)}", [])
    #     end

    # Pull the cast from the internal vocabulary so we do not have to dig into
    # each subschema's validators when validating.
    {cast, schema_validators} =
      case List.keytake(schema_validators, Vocabulary.Cast, 0) do
        nil -> {nil, schema_validators}
        {{Vocabulary.Cast, cast}, svs} -> {cast, svs}
      end

    # Reverse the list to keep the priority order from builder.vocabularies
    schema_validators = :lists.reverse(schema_validators)

    {
      %JSV.Subschema{validators: schema_validators, schema_path: rev_path, cast: cast},
      builder
    }
  end

  defp do_build_sub(valid?, rev_path, builder) when is_boolean(valid?) do
    {BooleanSchema.of(valid?, rev_path), builder}
  end

  defp mod_and_init_opts({module, opts}) when is_atom(module) and is_list(opts) do
    {module, opts}
  end

  defp mod_and_init_opts(module) when is_atom(module) do
    {module, []}
  end

  defp build_mod_validators(raw_pairs, module, init_opts, builder, raw_schema) when is_map(raw_schema) do
    {leftovers, mod_acc, builder} =
      Enum.reduce(raw_pairs, {[], module.init_validators(init_opts), builder}, fn pair, {leftovers, mod_acc, builder} ->
        # "keyword" refers to the schema keyword, e.g. "type", "properties", etc,
        # supported by a vocabulary.

        case module.handle_keyword(pair, mod_acc, builder, raw_schema) do
          {mod_acc, builder} -> {leftovers, mod_acc, builder}
          :ignore -> {[pair | leftovers], mod_acc, builder}
          other -> fail(builder, {:bad_return, other}, {module, :handle_keyword, [pair, mod_acc, builder, raw_schema]})
        end
      end)

    {leftovers, module.finalize_validators(mod_acc), builder}
  end

  @spec vocabulary_enabled?(t, module) :: boolean
  def vocabulary_enabled?(builder, vocab) do
    Enum.find_value(builder.vocabularies, false, fn
      ^vocab -> true
      {^vocab, _} -> true
      _ -> false
    end)
  end

  @vocabulary_impls %{
    # Draft 2020-12
    "https://json-schema.org/draft/2020-12/vocab/core" => Vocabulary.V202012.Core,
    "https://json-schema.org/draft/2020-12/vocab/validation" => Vocabulary.V202012.Validation,
    "https://json-schema.org/draft/2020-12/vocab/applicator" => Vocabulary.V202012.Applicator,
    "https://json-schema.org/draft/2020-12/vocab/content" => Vocabulary.V202012.Content,
    "https://json-schema.org/draft/2020-12/vocab/format-annotation" => Vocabulary.V202012.Format,
    "https://json-schema.org/draft/2020-12/vocab/format-assertion" => {Vocabulary.V202012.Format, assert: true},
    "https://json-schema.org/draft/2020-12/vocab/meta-data" => Vocabulary.V202012.MetaData,
    "https://json-schema.org/draft/2020-12/vocab/unevaluated" => Vocabulary.V202012.Unevaluated,

    # Draft 7 does not define vocabularies. The $vocabulary content is made-up
    # by the resolver so we can use the same architecture for keyword dispatch
    # and allow user overrides.
    "https://json-schema.org/draft-07/--fallback--vocab/core" => Vocabulary.V7.Core,
    "https://json-schema.org/draft-07/--fallback--vocab/validation" => Vocabulary.V7.Validation,
    "https://json-schema.org/draft-07/--fallback--vocab/applicator" => Vocabulary.V7.Applicator,
    "https://json-schema.org/draft-07/--fallback--vocab/content" => Vocabulary.V7.Content,
    "https://json-schema.org/draft-07/--fallback--vocab/format-annotation" => Vocabulary.V7.Format,
    "https://json-schema.org/draft-07/--fallback--vocab/format-assertion" => {Vocabulary.V7.Format, assert: true},
    "https://json-schema.org/draft-07/--fallback--vocab/meta-data" => Vocabulary.V7.MetaData
  }

  defp build_vocabulary_impls(user_mapped) do
    Map.merge(@vocabulary_impls, user_mapped)
  end

  defp load_vocabularies(builder, map) do
    impls = builder.vocabulary_impls

    vocabs =
      Enum.reduce(map, [], fn {uri, required?}, acc ->
        case Map.fetch(impls, uri) do
          {:ok, impl} -> [impl | acc]
          :error when required? -> fail(builder, {:unknown_vocabulary, uri}, nil)
          :error -> acc
        end
      end)

    sort_vocabularies([Vocabulary.Cast | vocabs])
  end

  defp sort_vocabularies(modules) do
    Enum.sort_by(modules, fn
      {module, _} -> module.priority()
      module -> module.priority()
    end)
  end

  # TODO if we want to fail on resolver errors, we need to keep the
  # current_rev_path when a ref is staged. Currently those are resolved at the
  # top level and the buil path is just [:root] or [ns].
  @spec fail(t, term, term) :: no_return()
  def fail(%__MODULE__{} = builder, reason, action) do
    build_path = ErrorFormatter.format_schema_path(builder.current_rev_path)

    raise BuildError.of(reason, action, build_path)
  end
end
