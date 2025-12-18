defmodule JSV.Vocabulary.V202012.Validation do
  alias JSV.Builder
  alias JSV.Codec
  alias JSV.Helpers.Math
  alias JSV.Validator
  use JSV.Vocabulary, priority: 300

  @moduledoc """
  Implementation for the
  `https://json-schema.org/draft/2020-12/vocab/validation` vocabulary.
  """

  @impl true
  def init_validators(_) do
    []
  end

  take_keyword :type, t, vds, builder, _ do
    {[{:type, unwrap_ok(valid_type(t))} | vds], builder}
  end

  take_keyword :maximum, maximum, acc, builder, _ do
    take_number(:maximum, maximum, acc, builder)
  end

  take_keyword :exclusiveMaximum, exclusive_maximum, acc, builder, _ do
    take_number(:exclusiveMaximum, exclusive_maximum, acc, builder)
  end

  take_keyword :minimum, minimum, acc, builder, _ do
    take_number(:minimum, minimum, acc, builder)
  end

  take_keyword :exclusiveMinimum, exclusive_minimum, acc, builder, _ do
    take_number(:exclusiveMinimum, exclusive_minimum, acc, builder)
  end

  take_keyword :minItems, min_items, acc, builder, _ do
    take_integer(:minItems, min_items, acc, builder)
  end

  take_keyword :maxItems, max_items, acc, builder, _ do
    take_integer(:maxItems, max_items, acc, builder)
  end

  take_keyword :required, required when is_list(required), acc, builder, _ do
    {[{:required, required} | acc], builder}
  end

  take_keyword :multipleOf, zero when zero in [0, 0.0, -0.0], _acc, builder, _ do
    Builder.fail(builder, "mutipleOf zero is not allowed", :multipleOf)
  end

  take_keyword :multipleOf, multiple_of, acc, builder, _ do
    take_number(:multipleOf, multiple_of, acc, builder)
  end

  take_keyword :const, const, acc, builder, _ do
    {[{:const, const} | acc], builder}
  end

  take_keyword :maxLength, max_length, acc, builder, _ do
    take_integer(:maxLength, max_length, acc, builder)
  end

  take_keyword :minLength, min_length, acc, builder, _ do
    take_integer(:minLength, min_length, acc, builder)
  end

  take_keyword :minProperties, min_properties, acc, builder, _ do
    take_integer(:minProperties, min_properties, acc, builder)
  end

  take_keyword :maxProperties, max_properties, acc, builder, _ do
    take_integer(:maxProperties, max_properties, acc, builder)
  end

  take_keyword :enum, enum, acc, builder, _ do
    {[{:enum, enum} | acc], builder}
  end

  take_keyword :pattern, pattern, acc, builder, _ do
    re = unwrap_ok(Regex.compile(pattern))
    {[{:pattern, re} | acc], builder}
  end

  take_keyword :uniqueItems, unique?, acc, builder, _ do
    if unique? do
      {[{:uniqueItems, true} | acc], builder}
    else
      {acc, builder}
    end
  end

  take_keyword :dependentRequired, dependent_required, acc, builder, _ do
    {[{:dependentRequired, dependent_required} | acc], builder}
  end

  # minContains/maxContains is handled by the Applicator module IF the validation vocabulary is
  # enabled
  ignore_any_keyword()

  defp valid_type([h | t]) do
    with {:ok, new_t} <- valid_type(t),
         {:ok, new_h} <- valid_type(h) do
      {:ok, [new_h | new_t]}
    end
  end

  defp valid_type([]) do
    {:ok, []}
  end

  defp valid_type(type) do
    case type do
      "array" -> {:ok, :array}
      "object" -> {:ok, :object}
      "null" -> {:ok, :null}
      "boolean" -> {:ok, :boolean}
      "string" -> {:ok, :string}
      "integer" -> {:ok, :integer}
      "number" -> {:ok, :number}
      other -> {:error, {:invalid_type, other}}
    end
  end

  # ---------------------------------------------------------------------------

  @impl true
  def finalize_validators([]) do
    :ignore
  end

  def finalize_validators(list) do
    list
  end

  @impl true
  def validate(data, vds, vctx) do
    Validator.reduce(vds, data, vctx, &validate_keyword/3)
  end

  @doc false
  @spec validate_keyword({atom, Validator.validator()}, term, Validator.context()) :: Validator.result()
  def validate_keyword({:type, ts}, data, vctx) when is_list(ts) do
    found =
      Enum.find_value(ts, fn t ->
        case validate_type(data, t) do
          true -> {:ok, data}
          false -> nil
          {:swap, new_data} -> {:ok, new_data}
        end
      end)

    case found do
      {:ok, data} -> {:ok, data, vctx}
      nil -> {:error, Validator.with_error(vctx, :type, data, type: ts)}
    end
  end

  def validate_keyword({:type, t}, data, vctx) do
    case validate_type(data, t) do
      true -> {:ok, data, vctx}
      false -> {:error, Validator.with_error(vctx, :type, data, type: t)}
      {:swap, new_data} -> {:ok, new_data, vctx}
    end
  end

  def validate_keyword({:maximum, n}, data, vctx) when is_number(data) do
    case data <= n do
      true -> {:ok, data, vctx}
      false -> {:error, Validator.with_error(vctx, :maximum, data, n: n)}
    end
  end

  with_decimal do
    def validate_keyword({:maximum, n}, %Decimal{} = data, vctx) do
      case Decimal.lte?(data, to_decimal(n)) do
        true -> {:ok, data, vctx}
        false -> {:error, Validator.with_error(vctx, :maximum, data, n: n)}
      end
    end
  end

  pass validate_keyword({:maximum, _})

  def validate_keyword({:exclusiveMaximum, n}, data, vctx) when is_number(data) do
    case data < n do
      true -> {:ok, data, vctx}
      false -> {:error, Validator.with_error(vctx, :exclusiveMaximum, data, n: n)}
    end
  end

  with_decimal do
    def validate_keyword({:exclusiveMaximum, n}, %Decimal{} = data, vctx) do
      case Decimal.lt?(data, to_decimal(n)) do
        true -> {:ok, data, vctx}
        false -> {:error, Validator.with_error(vctx, :exclusiveMaximum, data, n: n)}
      end
    end
  end

  pass validate_keyword({:exclusiveMaximum, _})

  def validate_keyword({:minimum, n}, data, vctx) when is_number(data) do
    case data >= n do
      true -> {:ok, data, vctx}
      false -> {:error, Validator.with_error(vctx, :minimum, data, n: n)}
    end
  end

  with_decimal do
    def validate_keyword({:minimum, n}, %Decimal{} = data, vctx) do
      case Decimal.gte?(data, to_decimal(n)) do
        true -> {:ok, data, vctx}
        false -> {:error, Validator.with_error(vctx, :minimum, data, n: n)}
      end
    end
  end

  pass validate_keyword({:minimum, _})

  def validate_keyword({:exclusiveMinimum, n}, data, vctx) when is_number(data) do
    case data > n do
      true -> {:ok, data, vctx}
      false -> {:error, Validator.with_error(vctx, :exclusiveMinimum, data, n: n)}
    end
  end

  with_decimal do
    def validate_keyword({:exclusiveMinimum, n}, %Decimal{} = data, vctx) do
      case Decimal.gt?(data, to_decimal(n)) do
        true -> {:ok, data, vctx}
        false -> {:error, Validator.with_error(vctx, :exclusiveMinimum, data, n: n)}
      end
    end
  end

  pass validate_keyword({:exclusiveMinimum, _})

  def validate_keyword({:maxItems, max}, data, vctx) when is_list(data) do
    len = length(data)

    if len <= max do
      {:ok, data, vctx}
    else
      {:error, Validator.with_error(vctx, :maxItems, data, maxItems: max, len: len)}
    end
  end

  pass validate_keyword({:maxItems, _})

  def validate_keyword({:minItems, min}, data, vctx) when is_list(data) do
    len = length(data)

    if len >= min do
      {:ok, data, vctx}
    else
      {:error, Validator.with_error(vctx, :minItems, data, minItems: min, len: len)}
    end
  end

  pass validate_keyword({:minItems, _})

  def validate_keyword({:multipleOf, n}, data, vctx) when is_number(data) do
    case Math.fractional_is_zero?(data / n) do
      true -> {:ok, data, vctx}
      false -> {:error, Validator.with_error(vctx, :multipleOf, data, multipleOf: n)}
    end
  rescue
    # Rescue infinite division (huge numbers divided by float, too large invalid
    # floats)
    _ in ArithmeticError -> {:error, Validator.with_error(vctx, :arithmetic_error, data, context: "multipleOf")}
  end

  with_decimal do
    def validate_keyword({:multipleOf, n}, %Decimal{} = data, vctx) do
      data
      |> Decimal.rem(to_decimal(n))
      |> Decimal.eq?(0)
      |> case do
        true -> {:ok, data, vctx}
        false -> {:error, Validator.with_error(vctx, :multipleOf, data, multipleOf: n)}
      end
    rescue
      _ in Decimal.Error -> {:error, Validator.with_error(vctx, :arithmetic_error, data, context: "multipleOf")}
    end
  end

  pass validate_keyword({:multipleOf, _})

  def validate_keyword({:required, required_keys}, data, vctx) when is_map(data) do
    case required_keys -- Map.keys(data) do
      [] -> {:ok, data, vctx}
      missing -> {:error, Validator.with_error(vctx, :required, data, required: missing)}
    end
  end

  pass validate_keyword({:required, _})

  def validate_keyword({:dependentRequired, dependent_required}, data, vctx) do
    validate_dependent_required(dependent_required, data, vctx)
  end

  def validate_keyword({:maxLength, max}, data, vctx) when is_binary(data) do
    len = String.length(data)

    if len <= max do
      {:ok, data, vctx}
    else
      {:error, Validator.with_error(vctx, :maxLength, data, maxLength: max, len: len)}
    end
  end

  pass validate_keyword({:maxLength, _})

  def validate_keyword({:minLength, min}, data, vctx) when is_binary(data) do
    len = String.length(data)

    if len >= min do
      {:ok, data, vctx}
    else
      {:error, Validator.with_error(vctx, :minLength, data, minLength: min, len: len)}
    end
  end

  pass validate_keyword({:minLength, _})

  def validate_keyword({:const, const}, data, vctx) do
    # 1 == 1.0 should be true according to JSON Schema specs
    if data == const do
      {:ok, data, vctx}
    else
      {:error, Validator.with_error(vctx, :const, data, const: const)}
    end
  end

  def validate_keyword({:enum, enum}, data, vctx) do
    # validate 1 == 1.0 or 1.0 == 1
    if Enum.any?(enum, &(&1 == data)) do
      {:ok, data, vctx}
    else
      {:error, Validator.with_error(vctx, :enum, data, enum: enum)}
    end
  end

  def validate_keyword({:pattern, re}, data, vctx) when is_binary(data) do
    if Regex.match?(re, data) do
      {:ok, data, vctx}
    else
      {:error, Validator.with_error(vctx, :pattern, data, pattern: re.source)}
    end
  end

  pass validate_keyword({:pattern, _})

  def validate_keyword({:uniqueItems, true}, data, vctx) when is_list(data) do
    data
    |> Enum.with_index()
    |> Enum.reduce({[], %{}}, fn {item, index}, {duplicate_indices, seen} ->
      case Map.fetch(seen, item) do
        {:ok, seen_index} -> {[{index, seen_index} | duplicate_indices], seen}
        :error -> {duplicate_indices, Map.put(seen, item, index)}
      end
    end)
    |> case do
      {[], _} -> {:ok, data, vctx}
      {duplicates, _} -> {:error, Validator.with_error(vctx, :uniqueItems, data, duplicates: Map.new(duplicates))}
    end
  end

  pass validate_keyword({:uniqueItems, true})

  def validate_keyword({:minProperties, n}, data, vctx) when is_map(data) do
    case map_size(data) do
      size when size < n -> {:error, Validator.with_error(vctx, :minProperties, data, minProperties: n, size: size)}
      _ -> {:ok, data, vctx}
    end
  end

  pass validate_keyword({:minProperties, _})

  def validate_keyword({:maxProperties, n}, data, vctx) when is_map(data) do
    case map_size(data) do
      size when size > n -> {:error, Validator.with_error(vctx, :maxProperties, data, maxProperties: n, size: size)}
      _ -> {:ok, data, vctx}
    end
  end

  pass validate_keyword({:maxProperties, _})

  # ---------------------------------------------------------------------------

  # Shared to support "dependencies" compatibility
  @doc false
  @spec validate_dependent_required(Validator.validator(), term, Validator.context()) :: Validator.result()
  def validate_dependent_required(dependent_required, data, vctx) when is_map(data) do
    all_keys = Map.keys(data)

    Validator.reduce(dependent_required, data, vctx, fn
      {parent_key, required_keys}, data, vctx when is_map_key(data, parent_key) ->
        case required_keys -- all_keys do
          [] ->
            {:ok, data, vctx}

          missing ->
            {:error, Validator.with_error(vctx, :dependentRequired, data, parent: parent_key, missing: missing)}
        end

      {_, _}, data, vctx ->
        {:ok, data, vctx}
    end)
  end

  def validate_dependent_required(_other, data, vctx) do
    {:ok, data, vctx}
  end

  defp validate_type(data, :array) do
    is_list(data)
  end

  with_decimal do
    defp validate_type(%Decimal{}, :object) do
      false
    end
  end

  defp validate_type(data, :object) do
    is_map(data)
  end

  defp validate_type(data, :null) do
    data === nil
  end

  defp validate_type(data, :boolean) do
    is_boolean(data)
  end

  defp validate_type(data, :string) do
    is_binary(data)
  end

  defp validate_type(data, :integer) when is_float(data) do
    Math.fractional_is_zero?(data) && {:swap, trunc(data)}
  end

  defp validate_type(data, :integer) when is_integer(data) do
    true
  end

  defp validate_type(data, :number) when is_number(data) do
    true
  end

  with_decimal do
    defp validate_type(%Decimal{} = data, :integer) do
      if Decimal.integer?(data) do
        {:swap, Decimal.to_integer(data)}
      else
        false
      end
    end

    defp validate_type(%Decimal{}, :number) do
      true
    end
  end

  defp validate_type(_, t) when t in [:number, :integer] do
    false
  end

  # ---------------------------------------------------------------------------

  def format_error(:type, args, _) do
    %{type: type} = args
    types_format = type |> List.wrap() |> Enum.map_intersperse(" or ", &Atom.to_string/1)
    "value is not of type #{types_format}"
  end

  def format_error(:minimum, %{n: n}, data) do
    "value #{data} is lower than minimum #{n}"
  end

  def format_error(:exclusiveMinimum, %{n: n}, data) do
    "value #{data} is not higher than exclusive minimum #{n}"
  end

  def format_error(:maximum, %{n: n}, data) do
    "value #{data} is higher than maximum #{n}"
  end

  def format_error(:exclusiveMaximum, %{n: n}, data) do
    "value #{data} is not lower than exclusive maximum #{n}"
  end

  def format_error(:minLength, %{len: len, minLength: min_length}, _data) do
    "value length must be at least #{min_length} but is #{len}"
  end

  def format_error(:maxLength, %{len: len, maxLength: max_length}, _data) do
    "value length must be at most #{max_length} but is #{len}"
  end

  def format_error(:const, %{const: const}, _data) do
    "value should be #{Codec.encode!(const)}"
  end

  def format_error(:required, %{required: required}, _data) do
    case required do
      [single] -> "property #{quote_prop(single)} is required"
      _ -> "properties #{required |> Enum.map(&quote_prop/1) |> verbose_list("and")} are required"
    end
  end

  def format_error(:multipleOf, %{multipleOf: multiple_of}, data) do
    "value #{data} is not a multiple of #{multiple_of}"
  end

  def format_error(:pattern, %{pattern: pattern}, _data) do
    "value does not conform to pattern /#{pattern}/"
  end

  def format_error(:maxItems, %{len: len, maxItems: max_items}, _data) do
    "value should have at most #{max_items} items, got #{len}"
  end

  def format_error(:minItems, %{len: len, minItems: min_items}, _data) do
    "value should have at least #{min_items} items, got #{len}"
  end

  def format_error(:minProperties, %{size: size, minProperties: min_properties}, _data) do
    "value must have at least #{min_properties} properties, got #{size}"
  end

  def format_error(:maxProperties, %{size: size, maxProperties: max_properties}, _data) do
    "value must have at most #{max_properties} properties, got #{size}"
  end

  def format_error(:enum, %{enum: enum}, _data) do
    "value must be one of the enum values: #{enum |> Enum.map(&inspect/1) |> verbose_list("or")}"
  end

  def format_error(:dependentRequired, %{parent: parent, missing: missing}, _data) do
    case missing do
      [single] ->
        "property #{quote_prop(single)} is required when property #{quote_prop(parent)} is present"

      _ ->
        "properties #{missing |> Enum.map(&quote_prop/1) |> verbose_list("and")} are required when property #{quote_prop(parent)} is present"
    end
  end

  def format_error(:uniqueItems, %{duplicates: duplicates}, _data) do
    printout =
      Enum.map(duplicates, fn {dup_index, seen_index} ->
        "values at indices #{seen_index} and #{dup_index} are equal"
      end)

    "value must contain unique items but #{verbose_list(printout, "and")}"
  end

  @impl true
  def format_error(:arithmetic_error, %{context: context}, data) do
    "could not valiade #{inspect(data)}, got arithmetic error in context #{quote_prop(context)}"
  end

  defp verbose_list([single], _) do
    single
  end

  defp verbose_list([_ | _] = list, operator) do
    [last | [_ | _] = rest] = :lists.reverse(list)
    rest = :lists.reverse(rest)
    [Enum.intersperse(rest, ", "), " ", operator, " ", last]
  end

  defp quote_prop(val) do
    ["'", val, "'"]
  end
end
