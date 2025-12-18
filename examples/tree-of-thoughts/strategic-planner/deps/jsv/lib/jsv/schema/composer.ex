defmodule JSV.Schema.Composer do
  alias JSV.Schema
  import JSV.Schema.HelperCompiler

  @moduledoc """
  This module contains a composable API to build schemas in a functionnal way.

  Every function will return a schema and accepts an optional _first_ argument
  to merge onto, using `JSV.Schema.merge/2`.

  See `JSV.Schema.Helpers` to work with a more "presets" oriented API.

  ## Example

      iex> %JSV.Schema{}
      ...> |> object()
      ...> |> properties(foo: string())
      ...> |> required([:foo])
      %JSV.Schema{type: :object, properties: %{foo: %JSV.Schema{type: :string}}, required: [:foo]}
  """

  @type property_key :: atom | binary
  @type properties :: [{property_key, Schema.schema()}] | %{optional(property_key) => Schema.schema()}

  defcompose :boolean, type: :boolean

  defcompose :integer, type: :integer
  defcompose :number, type: :number
  defcompose :pos_integer, type: :integer, minimum: 1
  defcompose :non_neg_integer, type: :integer, minimum: 0
  defcompose :neg_integer, type: :integer, maximum: -1

  @doc """
  See `props/2` to define the properties as well.
  """
  defcompose :object, type: :object

  @doc """
  Does **not** set the `type: :array` on the schema. Use `array_of/2` for a
  shortcut.
  """
  defcompose :items, items: item_schema :: Schema.schema()
  defcompose :array_of, type: :array, items: item_schema :: Schema.schema()

  defcompose :string, type: :string
  defcompose :date, type: :string, format: :date
  defcompose :datetime, type: :string, format: :"date-time"
  defcompose :uri, type: :string, format: :uri
  defcompose :uuid, type: :string, format: :uuid
  defcompose :email, type: :string, format: :email
  defcompose :non_empty_string, type: :string, minLength: 1

  @doc """
  Does **not** set the `type: :string` on the schema. Use `string_of/2` for a
  shortcut.
  """
  defcompose :format, [format: format] when is_binary(format) when is_atom(format)
  defcompose :string_of, [type: :string, format: format] when is_binary(format) when is_atom(format)

  @doc """
  A struct-based schema module name is not a valid reference. Modules should be
  passed directly where a schema (and not a `$ref`) is expected.

  #### Example

  For instance to define a `user` property, this is valid:
  ```
  props(user: UserSchema)
  ```

  The following is invalid:
  ```
  # Do not do this
  props(user: ref(UserSchema))
  ```
  """
  defcompose :ref, "$ref": ref :: String.t()

  @doc """
  Does **not** set the `type: :object` on the schema. Use `props/2` for a
  shortcut.
  """
  defcompose :properties,
             [
               properties: Map.new(properties) <- properties :: properties
             ]
             when is_list(properties)
             when is_map(properties)

  defcompose :props,
             [
               type: :object,
               properties: Map.new(properties) <- properties :: properties
             ]
             when is_list(properties)
             when is_map(properties)

  defcompose :all_of, [allOf: schemas :: [Schema.schema()]] when is_list(schemas)
  defcompose :any_of, [anyOf: schemas :: [Schema.schema()]] when is_list(schemas)
  defcompose :one_of, [oneOf: schemas :: [Schema.schema()]] when is_list(schemas)

  defcompose :string_to_integer, type: :string, "jsv-cast": JSV.Cast.string_to_integer()
  defcompose :string_to_float, type: :string, "jsv-cast": JSV.Cast.string_to_float()
  defcompose :string_to_number, type: :string, "jsv-cast": JSV.Cast.string_to_number()
  defcompose :string_to_boolean, type: :string, "jsv-cast": JSV.Cast.string_to_boolean()
  defcompose :string_to_existing_atom, type: :string, "jsv-cast": JSV.Cast.string_to_existing_atom()
  defcompose :string_to_atom, type: :string, "jsv-cast": JSV.Cast.string_to_atom()

  @doc """
  Accepts a list of atoms and validates that a given value is a string
  representation of one of the given atoms.

  On validation, a cast will be made to return the original atom value.

  This is useful when dealing with enums that are represented as atoms in the
  codebase, such as Oban job statuses or other Ecto enum types.

      iex> schema = JSV.Schema.props(status: JSV.Schema.Composer.string_to_atom_enum([:executing, :pending]))
      iex> root = JSV.build!(schema)
      iex> JSV.validate(%{"status" => "pending"}, root)
      {:ok, %{"status" => :pending}}

  > #### Does not support `nil` {: .warning}
  >
  > This function sets the `string` type on the schema. If `nil` is given in the
  > enum, the corresponding valid JSON value will be the `"nil"` string rather
  > than `null`
  """
  defcompose :string_to_atom_enum,
             [
               type: :string,
               # We need to cast atoms to string, otherwise if `nil` is provided
               # it will be JSON-encoded as `nil` instead of `"null". But this
               # caster only accepts strings.
               enum: Enum.map(enum, &Atom.to_string/1) <- enum :: [atom],
               "jsv-cast": JSV.Cast.string_to_atom()
             ]
             when is_list(enum)

  @doc """
  Defines a JSON Schema with `required: keys` or adds the given `keys` if the
  [base schema](JSV.Schema.html#merge/2) already has a `:required`
  definition.

  Existing required keys are preserved.

  ### Examples

      iex> JSV.Schema.required(%{}, [:a, :b])
      %{required: [:a, :b]}

      iex> JSV.Schema.required(%{required: nil}, [:a, :b])
      %{required: [:a, :b]}

      iex> JSV.Schema.required(%{required: [:c]}, [:a, :b])
      %{required: [:a, :b, :c]}

      iex> JSV.Schema.required(%{required: [:a]}, [:a])
      %{required: [:a, :a]}

  Use `JSV.Schema.merge/2` to replace existing required keys.

      iex> JSV.Schema.merge(%{required: [:a, :b, :c]}, required: [:x, :y, :z])
      %{required: [:x, :y, :z]}
  """
  @spec required(Schema.merge_base(), [atom | binary]) :: Schema.schema()
  def required(merge_base \\ nil, key_or_keys)

  def required(nil, keys) when is_list(keys) do
    Schema.new(required: keys)
  end

  def required(merge_base, keys) when is_list(keys) do
    case Schema.merge(merge_base, []) do
      %{required: list} = map when is_list(list) -> Schema.merge(map, required: keys ++ list)
      map -> Schema.merge(map, required: keys)
    end
  end
end
