defmodule JSV.Schema.Helpers do
  alias JSV.Schema
  import JSV.Schema.HelperCompiler

  @moduledoc """
  Helpers to define schemas in plain Elixir code.
  """

  @schema_presets_doc """
  Schema presets are functions that take zero or more arguments and return
  predefined schemas. Those predefined schemas are _not_ `JSV.Schema` structs
  but raw maps.

  Each function has a second version with an additional `extra` argument that
  will be combined with the predefined schema using `JSV.Schema.combine/2`.

  Note that the `extra` attributes cannot override what is defined in the
  preset.

  ### Example

      %{
        properties: %{
          foo: integer(),
          bar: integer(description: "An actual bar", minimum: 10),
          baz: any_of([MyApp.Baz,MyApp.OldBaz], description: "Baz baz baz")
        }
      }
  """

  @moduledoc groups: [
               %{title: "Schema Presets", description: @schema_presets_doc}
             ]

  @type property_key :: atom | binary
  @type properties :: [{property_key, Schema.schema()}] | %{optional(property_key) => Schema.schema()}

  @doc """
  The Schema Description sigil.

  A sigil used to embed long texts in schemas descriptions. Replaces all
  combinations of whitespace by a single whitespace and trims the string.

  It does not support any modifier.

  Note that newlines are perfectly fine in schema descriptions, as they are
  simply encoded as `"\\n"`. This sigil is intended for schemas that need to be
  compressed because they are sent over the wire repeatedly (like in HTTP APIs
  or when working with LLMs).

  ### Example

      iex> ~SD\"""
      ...> This schema represents an elixir.
      ...>
      ...> An elixir is a potion with positive outcomes!
      ...> \"""
      "This schema represents an elixir. An elixir is a potion with positive outcomes!"
  """
  defmacro sigil_SD({:<<>>, _, [description]}, []) do
    formatted = description |> String.replace(~r{\s+}, " ") |> String.trim()

    quote do
      unquote(formatted)
    end
  end

  @doc """
  An alias for `JSV.Schema.combine/2`.

  ### Example

      iex> object(description: "a user")
      ...> ~> any_of([AdminSchema, CustomerSchema])
      ...> ~> properties(foo: integer())
      %{
        type: :object,
        description: "a user",
        properties: %{foo: %{type: :integer}},
        anyOf: [AdminSchema, CustomerSchema]
      }
  """
  defdelegate left ~> right, to: JSV.Schema, as: :combine

  defpreset :boolean, type: :boolean

  defpreset :integer, type: :integer
  defpreset :number, type: :number
  defpreset :pos_integer, type: :integer, minimum: 1
  defpreset :non_neg_integer, type: :integer, minimum: 0
  defpreset :neg_integer, type: :integer, maximum: -1

  defpreset :all_of, [allOf: schemas :: [Schema.schema()]] when is_list(schemas)
  defpreset :any_of, [anyOf: schemas :: [Schema.schema()]] when is_list(schemas)
  defpreset :one_of, [oneOf: schemas :: [Schema.schema()]] when is_list(schemas)

  defpreset :string_to_integer, type: :string, "jsv-cast": JSV.Cast.string_to_integer()
  defpreset :string_to_float, type: :string, "jsv-cast": JSV.Cast.string_to_float()
  defpreset :string_to_number, type: :string, "jsv-cast": JSV.Cast.string_to_number()
  defpreset :string_to_boolean, type: :string, "jsv-cast": JSV.Cast.string_to_boolean()
  defpreset :string_to_existing_atom, type: :string, "jsv-cast": JSV.Cast.string_to_existing_atom()
  defpreset :string_to_atom, type: :string, "jsv-cast": JSV.Cast.string_to_atom()

  defpreset :string, type: :string
  defpreset :date, type: :string, format: :date
  defpreset :datetime, type: :string, format: :"date-time"
  defpreset :uri, type: :string, format: :uri
  defpreset :uuid, type: :string, format: :uuid
  defpreset :email, type: :string, format: :email
  defpreset :non_empty_string, type: :string, minLength: 1

  defpreset :array_of, type: :array, items: item_schema :: Schema.schema()

  @doc """
  Does **not** set the `type: :string` on the schema. Use `string_of/2` for a
  shortcut.
  """
  defpreset :format, [format: format] when is_binary(format) when is_atom(format)
  defpreset :string_of, [type: :string, format: format] when is_binary(format) when is_atom(format)

  @doc """
  Note that in the JSON Schema specification, if the enum contains `1` then
  `1.0` is a valid value.
  """
  defpreset :enum, [enum: enum :: list] when is_list(enum)

  defpreset :const, const: const :: term

  @doc """
  Accepts a list of atoms and returns a schema that validates  a string
  representation of one of the given atoms.

  On validation, a cast will be made to return the original atom value.

  This is useful when dealing with enums that are represented as atoms in the
  codebase, such as Oban job statuses or other Ecto enum types.

      iex> schema = props(status: string_enum_to_atom([:executing, :pending]))
      iex> root = JSV.build!(schema)
      iex> JSV.validate(%{"status" => "pending"}, root)
      {:ok, %{"status" => :pending}}

  > #### Does not support `nil` {: .warning}
  >
  > This function sets the `string` type on the schema. If `nil` is given in the
  > enum, the corresponding valid JSON value will be the `"nil"` string rather
  > than `null`. See `string_enum_to_atom_or_nil/2`.
  """
  defpreset :string_enum_to_atom,
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
  Like `string_enum_to_atom/2` but also accepts the `null` JSON value as part of the
  enum.
  """
  defpreset :string_enum_to_atom_or_nil,
            [
              type: [:string, :null],
              # We need to cast atoms to string, otherwise if `nil` is provided
              # it will be JSON-encoded as `nil` instead of `"null". But this
              # caster only accepts strings.
              enum: [nil | Enum.map(enum, &Atom.to_string/1)] <- enum :: [atom],
              "jsv-cast": JSV.Cast.string_to_atom_or_nil()
            ]
            when is_list(enum)

  @doc """
  See the `props/2` function that accepts properties as a first argument.
  """
  defpreset :object, type: :object

  @doc """
  Does **not** set the `type: :object` on the schema. Use `props/2` for a
  shortcut.
  """
  defpreset :properties,
            [
              properties: Map.new(properties) <- properties :: properties
            ]
            when is_list(properties)
            when is_map(properties)

  defpreset :props,
            [
              type: :object,
              properties: Map.new(properties) <- properties :: properties
            ]
            when is_list(properties)
            when is_map(properties)

  @doc """
  Returns a schema referencing the given `ref`.

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
  defpreset :ref, "$ref": ref :: String.t()

  @doc """
  Marks a schema as optional when using the keyword list syntax with
  `JSV.defschema/1`.

  This is useful for recursive module references where you want to avoid
  infinite nesting requirements. When used in property list syntax with
  `defschema`, the property will not be marked as required.

  #### Example

  ```
  defschema name: string(),
            parent: optional(MySelfReferencingModule)
  ```
  """
  @spec optional(term) :: {:optional, term}
  def optional(schema) do
    {:optional, schema}
  end
end
