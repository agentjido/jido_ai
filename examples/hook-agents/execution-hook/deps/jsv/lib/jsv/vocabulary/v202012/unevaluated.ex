defmodule JSV.Vocabulary.V202012.Unevaluated do
  alias JSV.Validator
  use JSV.Vocabulary, priority: 800

  @moduledoc """
  Implementation for the
  `https://json-schema.org/draft/2020-12/vocab/unevaluated` vocabulary.
  """

  @impl true
  def init_validators(_) do
    []
  end

  take_keyword :unevaluatedProperties, unevaluated_properties, acc, builder, _ do
    take_sub(:unevaluatedProperties, unevaluated_properties, acc, builder)
  end

  take_keyword :unevaluatedItems, unevaluated_items, acc, builder, _ do
    take_sub(:unevaluatedItems, unevaluated_items, acc, builder)
  end

  ignore_any_keyword()

  @impl true
  def finalize_validators([]) do
    :ignore
  end

  def finalize_validators(list) do
    Map.new(list)
  end

  @impl true
  def validate(data, vds, vctx) do
    Validator.reduce(vds, data, vctx, &validate_keyword/3)
  end

  with_decimal do
    defp validate_keyword({:unevaluatedProperties, _}, %Decimal{} = data, vctx) do
      {:ok, data, vctx}
    end
  end

  defp validate_keyword({:unevaluatedProperties, subschema}, data, vctx) when is_map(data) do
    evaluated = Validator.list_evaluaded(vctx)

    data
    |> Enum.filter(fn {k, _v} -> k not in evaluated end)
    |> Validator.reduce(data, vctx, fn {k, v}, data, vctx ->
      case Validator.validate_in(v, k, :unevaluatedProperties, subschema, vctx) do
        {:ok, _, vctx} -> {:ok, data, vctx}
        {:error, vctx} -> {:error, vctx}
      end
    end)
  end

  passp validate_keyword({:unevaluatedProperties, _})

  defp validate_keyword({:unevaluatedItems, subschema}, data, vctx) when is_list(data) do
    evaluated = Validator.list_evaluaded(vctx)

    data
    |> Enum.with_index(0)
    |> Enum.reject(fn {_, index} -> index in evaluated end)
    |> Validator.reduce(data, vctx, fn {item, index}, data, vctx ->
      case Validator.validate_in(item, index, :unevaluatedItems, subschema, vctx) do
        {:ok, _, vctx} -> {:ok, data, vctx}
        {:error, vctx} -> {:error, vctx}
      end
    end)
  end

  passp validate_keyword({:unevaluatedItems, _})

  # ---------------------------------------------------------------------------

  @impl true
  def format_error(_, _, _data) do
    "unevaluated value did not conform to schema"
  end
end
