defmodule JSV.Vocabulary.V7.Applicator do
  alias JSV.Builder
  alias JSV.Validator
  alias JSV.Vocabulary.V202012.Applicator, as: Fallback
  use JSV.Vocabulary, priority: 200

  @moduledoc """
  Implementation of the applicator vocabulary with draft 7 sepecifiticies.
  """

  @impl true
  defdelegate init_validators(opts), to: Fallback

  @impl true
  take_keyword :additionalItems, items, acc, builder, _ do
    take_sub(:additionalItems, items, acc, builder)
  end

  take_keyword :items, items when is_map(items), acc, builder, _ do
    take_sub(:items, items, acc, builder)
  end

  take_keyword :items, items when is_list(items), acc, builder, _ do
    {subvalidators, builder} =
      Enum.map_reduce(items, builder, fn item, builder ->
        {_subvalidators, _builder} = Builder.build_sub!(item, [:items], builder)
      end)

    {[{:items, subvalidators} | acc], builder}
  end

  def handle_keyword(pair, acc, builder, raw_schema) do
    Fallback.handle_keyword(pair, acc, builder, raw_schema)
  end

  @impl true
  def finalize_validators([]) do
    :ignore
  end

  def finalize_validators(validators) do
    validators = finalize_items(validators)

    Fallback.finalize_validators(validators)
  end

  defp finalize_items(validators) do
    {items, validators} = Keyword.pop(validators, :items, nil)
    {additional_items, validators} = Keyword.pop(validators, :additionalItems, nil)

    case {items, additional_items} do
      {nil, nil} -> validators
      {item_map, _} when is_map(item_map) -> Keyword.put(validators, :jsv@array, {item_map, nil})
      some -> Keyword.put(validators, :jsv@array, some)
    end
  end

  @impl true
  def validate(data, vds, vctx) do
    Validator.reduce(vds, data, vctx, &validate_keyword/3)
  end

  # draft-7 supports items as a map or an array (which was replaced by prefix
  # items). This clause is for array.
  defp validate_keyword({:jsv@array, {items_schemas, additional_items_schema}}, data, vctx)
       when is_list(items_schemas) and (is_map(additional_items_schema) or is_nil(additional_items_schema)) and
              is_list(data) do
    prefix_stream = Enum.map(items_schemas, &{:items_as_prefix, &1})

    rest_stream = Stream.cycle([{:additionalItems, additional_items_schema}])
    all_stream = Stream.concat(prefix_stream, rest_stream)
    data_items_index = Stream.with_index(data)

    # Zipping items with their schemas. If the schema only specifies
    # prefixItems, then items_schema is nil and the zip will associate with nil.
    zipped =
      Enum.zip_with([data_items_index, all_stream], fn
        [{data_item, index}, {kind, schema}] -> {kind, index, data_item, schema}
      end)

    {validated_items, vctx} = Fallback.validate_items(zipped, data, vctx, __MODULE__)
    Validator.return(validated_items, vctx)
  end

  # Items is a map, we will not use additional items.
  defp validate_keyword({:jsv@array, {items_schema, _}}, data, vctx)
       when (is_map(items_schema) or (is_tuple(items_schema) and elem(items_schema, 0) == :alias_of)) and
              is_list(data) do
    all_stream = Stream.cycle([{:items, items_schema}])
    data_items_index = Enum.with_index(data)

    zipped =
      Enum.zip_with([data_items_index, all_stream], fn
        [{data_item, index}, {kind, schema}] -> {kind, index, data_item, schema}
      end)

    {validated_items, vctx} = Fallback.validate_items(zipped, data, vctx, __MODULE__)
    Validator.return(validated_items, vctx)
  end

  # this also passes when items schema is nil. In that case the additionalItems
  # schema is not used, every item is valid.
  passp validate_keyword({:jsv@array, _})

  defp validate_keyword(vd, data, vctx) do
    Fallback.validate_keyword(vd, data, vctx)
  end

  @impl true
  def format_error(:additionalItems, args, _) do
    %{index: index} = args
    "item at index #{index} does not validate the 'additionalItems' schema"
  end

  def format_error(:items_as_prefix, args, _) do
    %{index: index} = args
    "item at index #{index} does not validate the 'items[#{index}]' schema"
  end

  defdelegate format_error(key, args, data), to: Fallback
end
