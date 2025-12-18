defmodule JSV.Vocabulary.V202012.Core do
  alias JSV.Builder
  alias JSV.Key
  alias JSV.Ref
  alias JSV.Resolver.Resolved
  alias JSV.Validator
  alias JSV.Vocabulary
  use JSV.Vocabulary, priority: 100

  @moduledoc """
  Implementation for the `https://json-schema.org/draft/2020-12/vocab/core`
  vocabulary.
  """

  @impl true
  def init_validators(_) do
    []
  end

  take_keyword :"$ref", raw_ref, acc, builder, _ do
    ref = unwrap_ok(Ref.parse(raw_ref, builder.ns))
    {ref, builder} = maybe_swap_ref(ref, builder)
    put_ref(ref, :"$ref", acc, builder)
  end

  consume_keyword :"$defs"
  consume_keyword :"$anchor"

  take_keyword :"$dynamicRef", raw_ref, acc, builder, _ do
    # We need to ensure that the dynamic ref is in a schema where a
    # corresponding dynamic anchor is present. Otherwise we are just a normal
    # ref to an anchor (and we do not check its existence at this point.)

    case unwrap_ok(Ref.parse_dynamic(raw_ref, builder.ns)) do
      %{dynamic?: true, kind: :anchor, arg: anchor} = ref ->
        builder = Builder.ensure_resolved!(builder, ref)
        %{raw: raw} = Builder.fetch_resolved!(builder, ref.ns)

        case find_local_dynamic_anchor(raw, anchor) do
          :ok -> put_ref(ref, :"$dynamicRef", acc, builder)
          {:error, {:no_such_dynamic_anchor, _}} -> put_ref(%{ref | dynamic?: false}, :"$dynamicRef", acc, builder)
        end

      %{dynamic?: false} = ref ->
        put_ref(ref, :"$dynamicRef", acc, builder)
    end
  end

  consume_keyword :"$dynamicAnchor"
  consume_keyword :"$comment"
  consume_keyword :"$id"
  consume_keyword :"$schema"
  consume_keyword :"$vocabulary"
  ignore_any_keyword()

  @impl true
  def finalize_validators([]) do
    :ignore
  end

  def finalize_validators(list) do
    list
  end

  @doc false
  @spec put_ref(Ref.t() | binary, :"$ref" | :"$dynamicRef", Vocabulary.acc(), Builder.t()) ::
          {Vocabulary.acc(), Builder.t()}
  def put_ref(%Ref{} = ref, kind_as_eval_path, acc, builder) do
    builder = Builder.stage_build(builder, ref)
    {[{:ref, kind_as_eval_path, Key.of(ref)} | acc], builder}
  end

  # If the ref is a pointer but points to a schema with an $id we will swap the
  # ref to target that ID instead, so we can support skipping over boundaries
  # when resolving dynamic refs by not adding intermediary scopes.
  defp maybe_swap_ref(%{kind: :pointer} = ref, builder) do
    builder = Builder.ensure_resolved!(builder, ref)
    resolved = Builder.fetch_resolved!(builder, Key.of(ref))

    case resolved do
      %Resolved{raw: %{"$id" => _}, ns: ns} ->
        {:ok, new_ref} = Ref.parse(ns, builder.ns)
        {new_ref, builder}

      _ ->
        {ref, builder}
    end
  end

  defp maybe_swap_ref(ref, builder) do
    {ref, builder}
  end

  # Look for a dynamic anchor in this schema (that may have an $id) without
  # looking down in subschemas that define their own $id.

  defp find_local_dynamic_anchor(%{"$id" => _} = raw_schema, anchor) do
    with :error <- do_find_local_dynamic_anchor(Map.delete(raw_schema, "$id"), anchor) do
      {:error, {:no_such_dynamic_anchor, anchor}}
    end
  end

  defp do_find_local_dynamic_anchor(%{"$id" => _}, _anchor) do
    :error
  end

  defp do_find_local_dynamic_anchor(%{} = raw_schema, anchor) do
    case raw_schema do
      %{"$dynamicAnchor" => ^anchor} ->
        :ok

      %{} ->
        raw_schema
        |> Map.drop(["properties"])
        |> Map.values()
        |> do_find_local_dynamic_anchor(anchor)
    end
  end

  defp do_find_local_dynamic_anchor([h | t], anchor) do
    case do_find_local_dynamic_anchor(h, anchor) do
      :ok -> :ok
      :error -> do_find_local_dynamic_anchor(t, anchor)
    end
  end

  defp do_find_local_dynamic_anchor(other, _anchor)
       when other == []
       when is_binary(other)
       when is_atom(other)
       when is_number(other) do
    :error
  end

  # ---------------------------------------------------------------------------

  @impl true
  def validate(data, vds, vctx) do
    Validator.reduce(vds, data, vctx, &validate_keyword/3)
  end

  defp validate_keyword({:ref, eval_path, ref}, data, vctx) do
    Validator.validate_ref(data, ref, eval_path, vctx)
  end

  # ---------------------------------------------------------------------------
end
