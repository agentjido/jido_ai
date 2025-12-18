defmodule JSV.Normalizer do
  alias JSV.Helpers.Traverse

  @moduledoc """
  A Normalizer for JSON data structures.
  """

  @type json_decoded_form ::
          %{optional(String.t()) => json_decoded_form}
          | [json_decoded_form]
          | String.t()
          | number()
          | true
          | false
          | nil

  @doc """
  Returns the given term in a JSON-decoded form without general atoms or
  structs.

  See `normalize/3` for details and options.

  ### Examples


      iex> JSV.Normalizer.normalize(%{name: :joe})
      %{"name" => "joe"}

      iex> JSV.Normalizer.normalize(%{"name" => :joe})
      %{"name" => "joe"}

      iex> JSV.Normalizer.normalize(%{"name" => "joe"})
      %{"name" => "joe"}

      iex> JSV.Normalizer.normalize(%{true: false})
      %{"true" => false}

      iex> JSV.Normalizer.normalize(%{specials: [true, false, nil]})
      %{"specials" => [true, false, nil]}

  This function is also used internally to normalize schemas.

      iex> JSV.Normalizer.normalize(%JSV.Schema{title: nil, properties: nil})
      %{}

      iex> JSV.Normalizer.normalize(%JSV.Schema{type: :integer})
      %{"type" => "integer"}

      iex> JSV.Normalizer.normalize(%JSV.Schema{title: :"My Schema"})
      %{"title" => "My Schema"}

  Other structs must implement the `JSV.Normalizer.Normalize` protocol.

      iex> defimpl JSV.Normalizer.Normalize, for: Range do
      iex>   def normalize(range), do: Map.from_struct(range)
      iex> end
      iex> JSV.Normalizer.normalize(1..10)
      %{"first" => 1, "last" => 10, "step" => 1}
  """
  @spec normalize(term, keyword) :: json_decoded_form
  def normalize(term, opts \\ []) do
    {normalized, _acc} = normalize(term, [], opts)
    normalized
  end

  @doc """
  Returns the given term in a JSON-decoded form without general atoms or structs
  with an accumulator.

  ### What is "JSON-decoded" form?

  By that we mean that the returned data could have been returned by
  `JSON.decode!/1`:

  * Only maps, lists, strings, numbers and atoms.
  * Structs must implement the `JSV.Normalizer.Normalize` protocol.
  * `true`, `false` and `nil` will be kept as-is in all places except for map
    keys.
  * `true`, `false` and `nil` as map keys will be converted to string.
  * Other atoms as values will be passed to the `:on_general_atom` callback (see
    options).
  * Map keys must only be atoms, strings or numbers and will be converted to
    strings.

  ### Options

  * `:on_general_atom` - A callback accepting an atom found in the data and the
    accumulator. Must return a JSON-decoded value.

  ### Examples

      iex> on_general_atom = fn atom, acc ->
      ...>   {"found:\#{atom}", [atom|acc]}
      ...> end
      iex> opts = [on_general_atom: on_general_atom]
      iex> acc_in = []
      iex> JSV.Normalizer.normalize(%{an_atom: SomeAtom, a_string: "hello"}, acc_in, opts)
      {%{"an_atom" => "found:Elixir.SomeAtom", "a_string" => "hello"}, [SomeAtom]}
  """
  @spec normalize(term, term, keyword) :: {json_decoded_form, term}
  def normalize(term, acc_in, opts) when is_list(opts) do
    on_general_atom =
      case Keyword.fetch(opts, :on_general_atom) do
        {:ok, f} when is_function(f, 2) -> f
        :error -> &default_on_general_atom/2
      end

    Traverse.postwalk(term, acc_in, fn
      {:val, v}, acc when is_binary(v) when is_list(v) when is_map(v) when is_number(v) ->
        {v, acc}

      {:val, v}, acc when v in [true, false, nil] ->
        {v, acc}

      {:val, v}, acc when is_atom(v) ->
        on_general_atom.(v, acc)

      {:val, other}, _acc ->
        raise ArgumentError, "invalid value in JSON data: #{inspect(other)}"

      {:key, k}, acc when is_binary(k) ->
        {k, acc}

      {:key, k}, acc when is_atom(k) ->
        {Atom.to_string(k), acc}

      {:key, k}, acc when is_number(k) ->
        {to_string(k), acc}

      {:key, other}, _acc ->
        raise ArgumentError, "invalid key in JSON data: #{inspect(other)}"

      {:struct, %_{} = struct, cont}, acc ->
        cont.(JSV.Normalizer.Normalize.normalize(struct), acc)
    end)
  end

  @doc """
  Default implementation for the `:on_general_atom` option of `normalize/2` and
  `normalize/3`. Transforms atoms to strings.
  """
  @spec default_on_general_atom(atom, term) :: {String.t(), term}
  def default_on_general_atom(atom, acc) do
    {Atom.to_string(atom), acc}
  end
end
