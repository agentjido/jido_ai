defmodule Texture.HttpStructuredField do
  alias Texture.HttpStructuredField.Parser

  @moduledoc ~S"""
  HTTP Structured Field parser implementation following RFC 8941.

  This module exposes high-level helpers to parse the three Structured Field
  top-level types defined by the RFC:

    * items (single bare item with optional parameters)
    * lists (comma separated sequence of items or inner lists)
    * dictionaries (comma separated key / item pairs – bare keys imply a true boolean)

  Returned data is, by default, tagged with the parsed value type. You can opt
  into two orthogonal transformations using options:

    * `unwrap: true` – remove the type tag wrapper from items and attributes
    * `maps: true` – turn attribute collections and dictionaries into maps

  ## Shapes

  By default (no options):

    * item: `{type, value, attributes}`
    * attribute: `{key, {type, value}}`
    * inner list: `{:inner_list, [item, ...], attributes}`
    * dictionary: list of `{key, item}` tuples

  With `unwrap: true`:

    * item: `{value, attributes}` (type tag removed)
    * attribute: `{key, value}`
    * inner list: `{[unwrapped_item, ...], attributes}`

  With `maps: true`:

    * attribute collections (item / inner list parameters) become a `%{key => attr}` map
    * dictionary becomes a `%{key => item}` map

  Both options compose: `unwrap: true, maps: true` yields unwrapped values and
  maps for every attribute / dictionary collection.

  ## Parsing a single item

  An item with no parameters:

      iex> Texture.HttpStructuredField.parse_item("123")
      {:ok, {:integer, 123, []}}

  Item with boolean (implicit) and integer parameters:

      iex> Texture.HttpStructuredField.parse_item("123;a;b=5")
      {:ok, {:integer, 123, [{"a", {:boolean, true}}, {"b", {:integer, 5}}]}}

  Unwrapped (type tags removed):

      iex> Texture.HttpStructuredField.parse_item("123;a;b=5", unwrap: true)
      {:ok, {123, [{"a", true}, {"b", 5}]}}

  Attributes as a map (still wrapped):

      iex> Texture.HttpStructuredField.parse_item("123;a;b=5", maps: true)
      {:ok, {:integer, 123, %{"a" => {:boolean, true}, "b" => {:integer, 5}}}}

  Both together (unwrapped values and attribute map):

      iex> Texture.HttpStructuredField.parse_item("123;a;b=5", unwrap: true, maps: true)
      {:ok, {123, %{"a" => true, "b" => 5}}}

  ## Parsing a list

  A list can contain bare items and inner lists:

      iex> Texture.HttpStructuredField.parse_list("123, \"hi\";a=1, (1 2 3);p")
      {:ok,
      [
        {:integer, 123, []},
        {:string, "hi", [{"a", {:integer, 1}}]},
        {:inner_list,
          [{:integer, 1, []}, {:integer, 2, []}, {:integer, 3, []}],
          [{"p", {:boolean, true}}]}
      ]}

  Unwrapping removes all type tags recursively:

      iex> Texture.HttpStructuredField.parse_list("123, \"hi\";a=1, (1 2 3);p", unwrap: true)
      {:ok,
      [
        {123, []},
        {"hi", [{"a", 1}]},
        {[{1, []}, {2, []}, {3, []}], [{"p", true}]}
      ]}

  Using maps for attributes (note inner list parameter map):

      iex> Texture.HttpStructuredField.parse_list("123, \"hi\";a=1, (1 2 3);p", unwrap: true, maps: true)
      {:ok,
      [
        {123, %{}},
        {"hi", %{"a" => 1}},
        {[{1, %{}}, {2, %{}}, {3, %{}}], %{"p" => true}}
      ]}

  ## Parsing a dictionary

  Example with explicit and implicit boolean members plus inner list:

      iex> Texture.HttpStructuredField.parse_dict("foo=123, bar, baz=\"hi\";a=1;b=2, qux=(1 2);p")
      {:ok,
      [
        {"foo", {:integer, 123, []}},
        {"bar", {:boolean, true, []}},
        {"baz", {:string, "hi", [{"a", {:integer, 1}}, {"b", {:integer, 2}}]}},
        {"qux",
          {:inner_list, [{:integer, 1, []}, {:integer, 2, []}],
          [{"p", {:boolean, true}}]}}
      ]}

  Unwrapped:

      iex> Texture.HttpStructuredField.parse_dict("foo=123, bar, baz=\"hi\";a=1;b=2, qux=(1 2);p", unwrap: true)
      {:ok,
      [
        {"foo", {123, []}},
        {"bar", {true, []}},
        {"baz", {"hi", [{"a", 1}, {"b", 2}]}},
        {"qux", {[{1, []}, {2, []}], [{"p", true}]}}
      ]}

  As a map (still wrapped):

      iex> Texture.HttpStructuredField.parse_dict("foo=123, bar, baz=\"hi\";a=1;b=2, qux=(1 2);p", maps: true)
      {:ok,
      %{
        "bar" => {:boolean, true, %{}},
        "baz" => {:string, "hi", %{"a" => {:integer, 1}, "b" => {:integer, 2}}},
        "foo" => {:integer, 123, %{}},
        "qux" => {:inner_list, [{:integer, 1, %{}}, {:integer, 2, %{}}],
          %{"p" => {:boolean, true}}}
      }}

  Maps + Unwrapped:

      iex> Texture.HttpStructuredField.parse_dict("foo=123, bar, baz=\"hi\";a=1;b=2, qux=(1 2);p", unwrap: true, maps: true)
      {:ok,
      %{
        "bar" => {true, %{}},
        "baz" => {"hi", %{"a" => 1, "b" => 2}},
        "foo" => {123, %{}},
        "qux" => {[{1, %{}}, {2, %{}}], %{"p" => true}}
      }}

  ## Error handling

  On invalid input an `{:error, {reason, remainder}}` tuple is returned:

      iex> Texture.HttpStructuredField.parse_item("not@@valid")
      {:error, {:invalid_value, "not@@valid"}}

  The low-level tokenization lives in the private `Parser` module; only the
  post-processing (unwrap / maps) occurs here.
  """

  @type option :: {:maps, boolean} | {:unwrap, boolean}

  @type item :: wrapped_item | unwrapped_item
  @type wrapped_item :: {tag, value, attrs}
  @type unwrapped_item :: {value, attrs}
  @type tag :: :integer | :decimal | :string | :token | :byte_sequence | :boolean | :inner_list
  @type value :: term
  @type attrs :: Enumerable.t(attribute)
  @type attribute :: wrapped_attribute | unwrapped_attribute
  @type wrapped_attribute :: {binary, {tag, value}}
  @type unwrapped_attribute :: {binary, value}

  @spec parse_item(binary, [option]) :: {:ok, item} | {:error, term}
  def parse_item(input, opts \\ []) do
    with {:ok, input} <- trim_not_empty(input),
         {:ok, item, ""} <- Parser.parse_item(input) do
      {:ok, post_process_item(item, opts)}
    end
  end

  @spec parse_list(binary, [option]) :: {:ok, [item]} | {:error, term}
  def parse_list(input, opts \\ []) do
    with {:ok, input} <- trim_not_empty(input),
         {:ok, list, ""} <- Parser.parse_list(input) do
      {:ok, post_process_list(list, opts)}
    end
  end

  @spec parse_dict(binary, [option]) :: {:ok, Enumerable.t({binary, item})} | {:error, term}
  def parse_dict(input, opts \\ []) do
    with {:ok, input} <- trim_not_empty(input),
         {:ok, dict, ""} <- Parser.parse_dict(input) do
      {:ok, post_process_dict(dict, opts)}
    end
  end

  defp trim_not_empty(input) do
    case String.trim(input) do
      "" -> Parser.error(:empty, input)
      rest -> {:ok, rest}
    end
  end

  @spec post_process_item(item, [option]) :: item
  def post_process_item(elem, opts) do
    maps? = true == opts[:maps]
    unwrap? = true == opts[:unwrap]
    post_process_item(elem, unwrap?, maps?)
  end

  defp post_process_item(elem, false, false) do
    elem
  end

  defp post_process_item({type, value, params}, unwrap?, maps?)
       when type in [:integer, :decimal, :string, :token, :byte_sequence, :boolean] do
    params = post_process_params(params, unwrap?, maps?)

    if unwrap? do
      {value, params}
    else
      {type, value, params}
    end
  end

  defp post_process_item({:inner_list, items, params}, unwrap?, maps?) do
    params = post_process_params(params, unwrap?, maps?)
    items = Enum.map(items, &post_process_item(&1, unwrap?, maps?))

    if unwrap? do
      {items, params}
    else
      {:inner_list, items, params}
    end
  end

  @spec post_process_list([item], [option]) :: [item]
  def post_process_list(list, opts) do
    maps? = true == opts[:maps]
    unwrap? = true == opts[:unwrap]
    post_process_list(list, unwrap?, maps?)
  end

  defp post_process_list(list, false, false) do
    list
  end

  defp post_process_list(list, unwrap?, maps?) do
    Enum.map(list, &post_process_item(&1, unwrap?, maps?))
  end

  @spec post_process_dict(Enumerable.t({binary, item}), [option]) :: Enumerable.t({binary, item})
  def post_process_dict(dict, opts) do
    maps? = true == opts[:maps]
    unwrap? = true == opts[:unwrap]
    post_process_dict(dict, unwrap?, maps?)
  end

  defp post_process_dict(dict, false, false) do
    dict
  end

  defp post_process_dict(dict, unwrap?, maps?) do
    dict = Enum.map(dict, fn {key, value} -> {key, post_process_item(value, unwrap?, maps?)} end)

    if maps? do
      Map.new(dict)
    else
      dict
    end
  end

  defp post_process_params(params, unwrap?, maps?) do
    params =
      if unwrap? do
        unwrap_params(params)
      else
        params
      end

    params =
      if maps? do
        Map.new(params)
      else
        params
      end

    params
  end

  defp unwrap_params(params) do
    Enum.map(params, &unwrap_param/1)
  end

  defp unwrap_param({key, {_type, value}}) do
    {key, value}
  end
end
