defmodule JSV do
  alias JSV.BooleanSchema
  alias JSV.Builder
  alias JSV.BuildError
  alias JSV.ErrorFormatter
  alias JSV.Key
  alias JSV.Ref
  alias JSV.Resolver
  alias JSV.Resolver.Internal
  alias JSV.Root
  alias JSV.Schema
  alias JSV.ValidationError
  alias JSV.Validator
  alias JSV.Validator.ValidationContext
  use JSV.Debanger, records: [:build]
  require Record

  Record.defrecordp(:build_ctx, :build, builder: nil, validators: %{})

  @moduledoc """
  JSV is a JSON Schema Validator.

  This module is the main facade for the library.

  To start validating schemas you will need to go through the following steps:

  1. [Obtain a schema](guides/schemas/defining-schemas.md). Schemas can be
     defined in Elixir code, read from files, fetched remotely, _etc_.
  1. [Build a validation root](guides/build/build-basics.md) with `build/2` or
     `build!/2`.
  1. [Validate the data](guides/validation/validation-basics.md).

  ## Example

  Here is an example of the most simple way of using the library:

  ```elixir
  schema = %{
    type: :object,
    properties: %{
      name: %{type: :string}
    },
    required: [:name]
  }

  root = JSV.build!(schema)

  case JSV.validate(%{"name" => "Alice"}, root) do
    {:ok, data} ->
      {:ok, data}

    # Errors can be turned into JSON compatible data structure to send them as an
    # API response or for logging purposes.
    {:error, validation_error} ->
      {:error, JSON.encode!(JSV.normalize_error(validation_error))}
  end
  ```

  If you want to explore the different capabilities of the library, please refer
  to the guides provided in this documentation.
  """

  @typedoc """
  A schema in a JSON-decoded form: Only maps with binary keys and
  binary/number/boolean/nil values, or a boolean.

  The name refers to the process of _normalization_. A `t:native_schema/0` can
  be turned into a `t:normal_schema/0` with the help of
  `JSV.Schema.normalize/1`.
  """

  @moduledoc groups: [
               [title: "Types"],
               [
                 title: "Schema Validation API",
                 description: "The main API for JSV, used to build validation roots and validate data."
               ],
               [
                 title: "Schema Definition Macros",
                 description: "Macros to create module-based schemas and custom cast functions."
               ],
               [
                 title: "Custom Build API",
                 description:
                   "Low level build API to work with schemas embedded in larger documents such as an OpenAPI specification."
               ]
             ]

  @default_default_meta "https://json-schema.org/draft/2020-12/schema"

  @build_opts_schema NimbleOptions.new!(
                       resolver: [
                         type: {:or, [:atom, :mod_arg, {:list, {:or, [:atom, :mod_arg]}}]},
                         default: [],
                         doc: """
                         The `JSV.Resolver` behaviour implementation module to
                         retrieve schemas identified by an URL.

                         Accepts a `module`, a `{module, options}` tuple or a
                         list of those forms.

                         The options can be any term and will be given to the
                         `resolve/2` callback of the module.

                         The `JSV.Resolver.Embedded` and `JSV.Resolver.Internal`
                         will be automatically appended to support module-based
                         schemas and meta-schemas.
                         """
                       ],
                       default_meta: [
                         type: :string,
                         doc:
                           ~S(The meta schema to use for resolved schemas that do not define a `"$schema"` property.),
                         default: @default_default_meta
                       ],
                       formats: [
                         type: {:or, [:boolean, nil, {:list, :atom}]},
                         doc: """
                         Controls the validation of strings with the `"format"` keyword.

                         * `nil` - Format validation is enabled if to the meta-schema uses the format assertion vocabulary.
                         * `true` - Enforces validation with the default validator modules.
                         * `false` - Disables all format validation.
                         * `[Module1, Module2,...]` (A list of modules) - Format validation is enabled and
                            will use those modules as validators instead of the default format validator modules.
                            The default format validator modules can be included back in the list manually,
                            see `default_format_validator_modules/0`.

                         > #### Formats are disabled by the default meta-schema {: .warning}
                         >
                         > The default value for this option is `nil` to respect
                         > the JSON Schema specification where format validation
                         > is enabled via vocabularies.
                         >
                         > The default meta-schemas for the latest drafts (example: `#{@default_default_meta}`)
                         > do not enable format validation.
                         >
                         > You'll probably want this option to be set to `true`
                         > or a list of your own modules.

                         Worth noting, while this option does support providing your own formats,
                         the [official specification](https://json-schema.org/draft/2020-12/draft-bhutton-json-schema-validation-00#rfc.section.7.2.3)
                         recommends against it:

                         > Vocabularies do not support specifically declaring different value sets for keywords.
                         > Due to this limitation, and the historically uneven implementation of this keyword,
                         > it is RECOMMENDED to define additional keywords in a custom vocabulary rather than
                         > additional format attributes if interoperability is desired.
                         """,
                         default: nil
                       ],
                       vocabularies: [
                         type: {:map, :string, {:or, [:atom, :mod_arg]}},
                         doc: """
                         Allows to redefine modules implementing vocabularies.

                         This option accepts a map with vocabulary URIs as keys and implementations as values.
                         The URIs are not fetched by JSV and does not need to point to anything specific.
                         For instance, vocabulary URIs in the standard Draft 2020-12 meta-schema point to
                         human-readable documentation.

                         The given implementations will only be used if the meta-schema used to build a validation root
                         actually declare those URIs in their `$vocabulary` keyword.

                         For instance, to redefine how the `type` keyword and other validation keywords are handled,
                         one should pass the following map:

                             %{
                               "https://json-schema.org/draft/2020-12/vocab/validation" => MyCustomModule
                             }

                         Modules must implement the `JSV.Vocabulary` behaviour.

                         Implementations can also be passed options by wrapping them in a tuple:

                             %{
                              "https://json-schema.org/draft/2020-12/vocab/validation" => {MyCustomModule, foo: "bar"}
                             }
                         """,
                         default: %{}
                       ]
                     )

  @validate_opts_schema NimbleOptions.new!(
                          cast: [
                            type: :boolean,
                            default: true,
                            doc: """
                            Enables calling generic cast functions on validation.

                            This is based on the `jsv-cast` JSON Schema custom keyword
                            and is typically used by `defschema/1`.

                            While it is on by default, some specific casting features are enabled
                            separately, see option `:cast_formats`.
                            """
                          ],
                          cast_formats: [
                            type: :boolean,
                            default: false,
                            doc: """
                            When enabled, format validators will return casted values,
                            for instance a `Date` struct instead of the date as string.

                            It has no effect when the schema was not built with formats enabled.
                            """
                          ],
                          key: [
                            type: :any,
                            required: false,
                            doc: """
                            When specified, the validation will start in the schema at the given key
                            instead of using the root schema.

                            The key must have been built and returned by `build_key!/2`. The validation
                            does not accept to validate any Ref or pointer in the schema.

                            This is useful when validating with a JSON document that contains schemas but
                            is not itself a schema.
                            """
                          ]
                        )

  @type normal_schema :: boolean() | %{binary => normal_schema() | [normal_schema()]}

  @typedoc """
  A schema in native JSV/Elixir terms: maps with atoms, structs, and module.
  """
  @type native_schema :: boolean() | map() | module() | normal_schema()

  @type build_opt :: unquote(NimbleOptions.option_typespec(@build_opts_schema))
  @type validate_opt :: unquote(NimbleOptions.option_typespec(@validate_opts_schema))

  @opaque build_context :: record(:build_ctx, builder: Builder.t(), validators: Validator.validators())

  # ---------------------------------------------------------------------------
  #                           Schema Validation API
  # ---------------------------------------------------------------------------

  @doc_group "Schema Validation API"

  @doc """
  Builds the schema as a `#{inspect(Root)}` schema for validation.

  ### Options

  #{NimbleOptions.docs(@build_opts_schema)}
  """
  @doc group: @doc_group
  @spec build(native_schema(), [build_opt]) :: {:ok, Root.t()} | {:error, Exception.t()}
  def build(raw_schema, opts \\ []) do
    {:ok, build!(raw_schema, opts)}
  rescue
    e in BuildError ->
      {:error, e}

    e in UndefinedFunctionError ->
      %{module: m, function: f, arity: a} = e
      {:error, BuildError.of(e, {m, f, a})}
  end

  @doc """
  Same as `build/2` but raises on error. Errors are not normalized into a
  `JSV.BuildError` as `build/2` does.
  """
  @doc group: @doc_group
  @spec build!(JSV.native_schema(), [build_opt]) :: Root.t()
  def build!(raw_schema, opts \\ [])

  def build!(valid?, _opts) when is_boolean(valid?) do
    %Root{raw: valid?, root_key: :root, validators: %{root: BooleanSchema.of(valid?, [:root])}}
  end

  def build!(raw_schema, opts) when is_map(raw_schema) when is_atom(raw_schema) do
    ctx = build_init!(opts)
    {root_key, normal_schema, ctx} = build_add!(ctx, raw_schema)
    {^root_key, build_ctx(validators: validators)} = build_key!(ctx, root_key)

    %Root{raw: normal_schema, validators: validators, root_key: root_key}
  end

  @doc """
  Returns the list of format validator modules that are used when a schema is
  built with format validation enabled and the `:formats` option to `build/2` is
  `true`.
  """
  @doc group: @doc_group
  @spec default_format_validator_modules :: [module]
  def default_format_validator_modules do
    [JSV.FormatValidator.Default]
  end

  @doc """
  Returns the default meta schema used when the `:default_meta` option is not
  set in `build/2`.

  Currently returns #{inspect(@default_default_meta)}.
  """
  @doc group: @doc_group
  @spec default_meta :: binary
  def default_meta do
    @default_default_meta
  end

  @doc """
  Returns the schema representing errors returned by `normalize_error/1`.

  Because errors can be nested, the schema is recursive, so this function
  returns a module based schema (a module name).
  """
  @doc group: @doc_group
  @spec error_schema :: module
  def error_schema do
    JSV.ErrorFormatter.error_schema()
  end

  @doc """
  Returns a JSON compatible represenation of a `JSV.ValidationError` struct.

  See `JSV.ErrorFormatter.normalize_error/2` for options.

  When used without the `:atoms` keys option, a normalized error will correspond
  to the JSON schema returned by `error_schema/0`.
  """
  @doc group: @doc_group
  @spec normalize_error(ValidationError.t() | Validator.context() | [Validator.Error.t()], keyword) :: map()
  def normalize_error(error, opts \\ [])

  def normalize_error(%ValidationError{} = error, opts) do
    ErrorFormatter.normalize_error(error, opts)
  end

  def normalize_error(errors, opts) when is_list(errors) do
    normalize_error(ValidationError.of(errors), opts)
  end

  def normalize_error(%ValidationContext{} = validator, opts) do
    normalize_error(Validator.to_error(validator), opts)
  end

  @doc false
  # direct entrypoint for tests when we want to get the returned context.
  @spec validation_entrypoint(term, term, term) :: Validator.result()
  def validation_entrypoint(%JSV.Root{} = schema, data, opts) do
    %JSV.Root{validators: validators, root_key: root_key} = schema

    {key, opts} = Keyword.pop(opts, :key, root_key)

    case Map.fetch(validators, key) do
      {:ok, root_schema_validators} ->
        context = JSV.Validator.context(validators, key, opts)
        JSV.Validator.validate(data, root_schema_validators, context)

      :error ->
        raise ArgumentError, "validators are not defined for key #{inspect(key)}"
    end
  end

  @doc """
  Normalizes a resolver implementation to a list of `{module, options}` and
  appends the default resolvers if they are not already present in the list.

  ### Examples

      iex> JSV.resolver_chain(MyModule)
      [{MyModule, []}, {JSV.Resolver.Embedded, []}, {JSV.Resolver.Internal, []}]

      iex> JSV.resolver_chain([JSV.Resolver.Embedded, MyModule])
      [{JSV.Resolver.Embedded, []}, {MyModule, []}, {JSV.Resolver.Internal, []}]

      iex> JSV.resolver_chain([{JSV.Resolver.Embedded, []}, {MyModule, %{foo: :bar}}])
      [{JSV.Resolver.Embedded, []}, {MyModule, %{foo: :bar}}, {JSV.Resolver.Internal, []}]
  """
  @doc group: @doc_group
  @spec resolver_chain(resolvers :: module | {module, term} | list({module, term})) :: [{module, term}]
  def resolver_chain(resolver) do
    resolvers = List.wrap(resolver)

    do_resolver_chain(resolvers, [], %{add_embedded: true, add_internal: true})
  end

  defp do_resolver_chain([impl | rest], acc, flags) do
    {module, _} =
      impl =
      case impl do
        {module, opts} when is_atom(module) -> {module, opts}
        module when is_atom(module) -> {module, []}
      end

    flags =
      case module do
        JSV.Resolver.Embedded -> %{flags | add_embedded: false}
        JSV.Resolver.Internal -> %{flags | add_internal: false}
        _ -> flags
      end

    do_resolver_chain(rest, [impl | acc], flags)
  end

  defp do_resolver_chain([], acc, flags) do
    tail =
      case flags do
        %{add_embedded: true, add_internal: true} -> [{JSV.Resolver.Embedded, []}, {JSV.Resolver.Internal, []}]
        %{add_embedded: false, add_internal: true} -> [{JSV.Resolver.Internal, []}]
        %{add_embedded: true, add_internal: false} -> [{JSV.Resolver.Embedded, []}]
        _ -> []
      end

    :lists.reverse(acc, tail)
  end

  @doc """
  Validates and casts the data with the given schema. The schema must be a
  `JSV.Root` struct generated with `build/2`.

  > #### This function returns cast data {: .info}
  >
  >
  > * If the `:cast_formats` option is enabled, string values may be transformed
  >   in other data structures. Refer to the "Formats" section of the
  >   [Validation guide](validation-basics.html#formats) for more information.
  > * The JSON Schema specification states that `123.0` is a valid integer. This
  >   function will return `123` instead. This may return invalid data for
  >   floats with very large integer parts. As always when dealing with JSON and
  >   big decimal or extremely precise numbers, use strings.

  ### Options

  #{NimbleOptions.docs(@validate_opts_schema)}
  """
  @doc group: @doc_group
  @spec validate(term, JSV.Root.t(), [validate_opt]) :: {:ok, term} | {:error, Exception.t()}
  def validate(data, root, opts \\ [])

  def validate(data, %JSV.Root{} = root, opts) do
    case NimbleOptions.validate(opts, @validate_opts_schema) do
      {:ok, opts} ->
        case validation_entrypoint(root, data, opts) do
          {:ok, casted_data, _} -> {:ok, casted_data}
          {:error, %ValidationContext{} = validator} -> {:error, Validator.to_error(validator)}
        end

      {:error, _} = err ->
        err
    end
  end

  @doc group: @doc_group
  @spec validate!(term, JSV.Root.t(), keyword) :: term
  def validate!(data, root, opts \\ []) do
    case validate(data, root, opts) do
      {:ok, term} -> term
      {:error, e} -> raise e
    end
  end

  # From https://github.com/fishcakez/dialyze/blob/6698ae582c77940ee10b4babe4adeff22f1b7779/lib/mix/tasks/dialyze.ex#L168
  @doc false
  @spec otp_version :: String.t()
  def otp_version do
    major = :erlang.list_to_binary(:erlang.system_info(:otp_release))
    vsn_file = Path.join([:code.root_dir(), "releases", major, "OTP_VERSION"])

    try do
      vsn_file
      |> File.read!()
      |> String.split("\n", trim: true)
    else
      [full] -> full
      _ -> major
    catch
      :error, _ -> major
    end
  end

  # ---------------------------------------------------------------------------
  #                          Schema Definition Macros
  # ---------------------------------------------------------------------------

  @doc_group "Schema Definition Macros"

  @doc """
  Defines a struct in the calling module where the struct keys are the
  properties of the schema.

  The given schema must define the `type` keyword as `object` and must define a
  `properties` map. That map can be empty to define a struct without any key.
  Properties keys must be given as atoms.

  If a default value is given in a property schema, it will be used as the
  default value for the corresponding struct key. Otherwise, the default value
  will be `nil`. A default value is _not_ validated against the property schema
  itself.

      defmodule MyApp.UserSchema do
        import JSV

        defschema %{
          type: :object,
          properties: %{
            name: %{type: :string, default: ""},
            age: %{type: :integer, default: 123}
          }
        }
      end

      iex> %MyApp.UserSchema{}
      %MyApp.UserSchema{name: "", age: 123}

      iex> {:ok, root} = JSV.build(MyApp.UserSchema)
      iex> JSV.validate(%{"name" => "Alice"}, root)
      {:ok, %MyApp.UserSchema{name: "Alice", age: 123}}

  The `required` keyword is supported and must use atom keys as well.

      defmodule MyApp.WithRequired do
        import JSV

        defschema %{
          type: :object,
          properties: %{
            name: %{type: :string},
            age: %{type: :integer, default: 123}
          },
          required: [:name]
        }
      end

      iex> %MyApp.WithRequired{name: "Alice"}
      %MyApp.WithRequired{name: "Alice", age: 123}



  ### Property List Syntax

  Alternatively, you can use a keyword list to define the properties where each
  property is defined as `{key, schema}`. The following rules apply:

  - All properties without a `default` value are automatically marked as
    required and are enforced at the struct level.
  - The resulting schema will have `type: :object` set automatically.
  - The `title` of the schema is set as the last segment of the module name.

  This provides a more concise way to define simple object schemas.

      defmodule MyApp.UserKW do
        use JSV.Schema

        defschema name: string(default: ""),
                  age: integer(default: 123)
      end

      iex> %MyApp.UserKW{}
      %MyApp.UserKW{name: "", age: 123}

  ### Additional properties

  Additional properties are allowed by default.

  If your schema does not define `additionalProperties: false`, the validation
  will accept a map with additional properties, but the keys will not be added
  to the resulting struct as it would make an invalid struct.

      iex> {:ok, root} = JSV.build(MyApp.UserSchema)
      iex> data = %{"name" => "Alice", "extra" => "hello!"}
      iex> JSV.validate(data, root)
      {:ok, %MyApp.UserSchema{name: "Alice", age: 123}}

  If the `cast: false` option is given to `JSV.validate/3`, structs will not be
  created. In that case, the additional properties will be kept.

      iex> {:ok, root} = JSV.build(MyApp.UserSchema)
      iex> data = %{"name" => "Alice", "extra" => "hello!"}
      iex> JSV.validate(data, root, cast: false)
      {:ok, %{"name" => "Alice", "extra" => "hello!"}}

  It is also possible to collect additional properties in a new struct key by
  defining the `@additional_properties` attribute above the `defschema`
  expression. This property will have a default value of `%{}` (the empty map).

      defmodule MyApp.UserSchemaWithAdds do
        import JSV

        @additional_properties :adds
        defschema %{
          type: :object,
          properties: %{
            name: %{type: :string, default: ""},
            age: %{type: :integer, default: 123}
          }
        }
      end

      iex> {:ok, root} = JSV.build(MyApp.UserSchemaWithAdds)
      iex> data = %{"name" => "Alice", "extra" => "hello!"}
      iex> JSV.validate(data, root)
      {:ok, %MyApp.UserSchemaWithAdds{name: "Alice", age: 123, adds: %{"extra" => "hello!"}}}

  ### Ignoring struct keys

  Some keys can be defined in the schema but not included in the struct by using
  the `@skip_keys` module attribute. This is helpful when a property uses
  `const` but your code rather depends on the struct type.

  Keys listed in `@skip_keys` will still be validated according to the schema!

      defmodule MyApp.UserEvent do
        use JSV.Schema

        @skip_keys [:message_type]
        defschema message_type: const("user_event"),
                  user_id: integer(),
                  event: string()
      end

      iex> {:ok, root} = JSV.build(MyApp.UserEvent)
      iex> data = %{"message_type" => "user_event", "user_id" => 123, "event" => "login"}
      iex> {:ok, result} = JSV.validate(data, root)
      iex> result
      %MyApp.UserEvent{user_id: 123, event: "login"}

  ### Module references

  A module can reference another module in its properties.

      defmodule MyApp.CompanySchema do
        import JSV

        defschema %{
          type: :object,
          properties: %{
            name: %{type: :string},
            owner: MyApp.UserSchema
          }
        }
      end

      iex> root = JSV.build!(MyApp.CompanySchema)
      iex> data = %{"name" => "Schemas Inc.", "owner" => %{"name" => "Alice", "age" => 999}}
      iex> JSV.validate(data, root)
      {:ok, %MyApp.CompanySchema{
        name: "Schemas Inc.",
        owner: %MyApp.UserSchema{
          name: "Alice",
          age: 999
        }
      }}
  """
  @doc group: @doc_group
  defmacro defschema(schema_or_properties) do
    Module.register_attribute(__CALLER__.module, :additional_properties, [])

    quote bind_quoted: [schema_or_properties: schema_or_properties] do
      schema =
        if is_list(schema_or_properties) do
          JSV.StructSupport.props_to_schema(schema_or_properties, %{title: List.last(Module.split(__MODULE__))})
        else
          schema_or_properties
        end

      :ok = JSV.StructSupport.validate!(schema)

      skip_keys = Map.new(Module.get_attribute(__MODULE__, :skip_keys, []), &{&1, true})

      @jsv_keycast Map.filter(JSV.StructSupport.keycast_pairs(schema), fn {_bin, k} ->
                     not is_map_key(skip_keys, k)
                   end)
      # @jsv_keycast JSV.StructSupport.keycast_pairs(schema)
      {keys_no_defaults, default_pairs} = JSV.StructSupport.data_pairs_partition(schema)

      default_pairs =
        case Module.get_attribute(__MODULE__, :additional_properties, nil) do
          nil ->
            @additional_properties_key nil
            default_pairs

          k when is_atom(k) ->
            [{k, %{}} | default_pairs]

          other ->
            raise "invalid @additional_properties key, atom expected, got: #{inspect(other)}"
        end

      required = schema |> JSV.StructSupport.list_required() |> Enum.reject(&is_map_key(skip_keys, &1))

      @jsv_tag 0

      @jsv_schema Map.put(schema, :"jsv-cast", [Atom.to_string(__MODULE__), @jsv_tag])

      @enforce_keys required

      all_keys =
        Enum.filter(keys_no_defaults ++ default_pairs, fn
          {k, _} when is_map_key(skip_keys, k) -> false
          k when is_map_key(skip_keys, k) -> false
          _ -> true
        end)

      defstruct all_keys

      @deprecated "use #{inspect(__MODULE__)}.json_schema/0 instead"
      @doc false
      def schema do
        IO.warn(
          "the #{inspect(__MODULE__)}.schema/0 is deprecated and will not be automatically defined in future versions, " <>
            " use #{inspect(__MODULE__)}.json_schema/0 instead"
        )

        json_schema()
      end

      def json_schema do
        @jsv_schema
      end

      @doc false
      def __jsv__(@jsv_tag, data) do
        pairs = JSV.StructSupport.take_keycast(data, @jsv_keycast, @additional_properties)
        {:ok, struct!(__MODULE__, pairs)}
      end

      @doc false
      def __jsv__(:required) do
        @enforce_keys
      end

      defoverridable schema: 0
    end
  end

  @doc """
  Defines a new module with a JSON Schema struct.

  This macro is similar to `defschema/1` but it also takes a module name and
  defines a nested module in the context where it is called. An optional
  description can be given, used as the `@moduledoc` and the description when a
  keyword list of properties is given.

  The module's struct will automatically `@derive` `Jason.Encoder` and
  `JSON.Encoder` if those modules are found during compilation.

  ### Title and Description Behavior

  When passing properties as a keyword list instead of a schema, the `title` and
  `description` parameters are automatically applied to the generated schema:

  - `title` is set from the module name (without outer module prefix if any)
  - `description` is set from the description parameter

  When passing a full schema map, the title and description from the parameters
  are not applied - the schema map is used as-is. Only the `description`
  parameter is used as the module's `@moduledoc`.

  ### Examples

  Basic module definition with keyword list:

      defschema User,
        name: string(),
        age: integer(default: 0)

  Module with description using keyword list:

      defschema User,
                "A user in the system",
                name: string(),
                age: integer(default: 0)

  Module with full schema map:

      defschema User,
                "User schema",
                %{
                  type: :object,
                  title: "Custom Title",
                  description: "Custom Desc",
                  properties: %{
                    name: %{type: :string},
                    age: %{type: :integer, default: 18}
                  },
                  required: [:name]
                }

  ## Usage

  The created module can be used like any struct:

      %User{name: "Alice", age: 25}

  And as a JSON Schema for validation:

      {:ok, root} = JSV.build(User)
      JSV.validate(%{"name" => "Bob"}, root)
      #=> {:ok, %User{name: "Bob", age: 0}}

  ## Module References

  Modules can reference other modules in their properties:

      defschema Address,
                street: string(),
                city: string()

      defschema User,
                name: string(),
                address: Address

  Use `__MODULE__` for self-references:

      defschema Category,
                name: string(),
                parent: optional(__MODULE__)
  """
  @doc group: @doc_group
  defmacro defschema(module, description \\ nil, schema_or_properties) do
    # not giving the caller env so we do not expand the module name to its FQMN
    module_name = inspect(Macro.expand_literals(module, __ENV__))

    quoted =
      quote do
        defmodule unquote(module) do
          schema_or_properties = unquote(schema_or_properties)
          description = unquote(description)

          use JSV.Schema

          @moduledoc description

          schema =
            if is_list(schema_or_properties) do
              overrides = %{title: unquote(module_name), description: description}
              JSV.StructSupport.props_to_schema(schema_or_properties, overrides)
            else
              schema_or_properties
            end

          if Code.ensure_loaded?(JSON.Encoder) do
            @derive JSON.Encoder
          end

          if Code.ensure_loaded?(Jason.Encoder) do
            @derive Jason.Encoder
          end

          defschema schema
        end
      end

    # I'm not sure why ElixirLS points to this macro's line when using
    # go-to-definition on defined modules. This does not seem to solve it.
    Macro.update_meta(quoted, &Keyword.put(&1, :line, __CALLER__.line))
  end

  @doc false
  defmacro defschema_for(target, schema) do
    quote bind_quoted: binding() do
      :ok = JSV.StructSupport.validate!(schema)
      @target target
      @jsv_keycast JSV.StructSupport.keycast_pairs(schema, target)
      {_keys_no_defaults, default_pairs} = JSV.StructSupport.data_pairs_partition(schema)
      @default_pairs default_pairs

      @jsv_tag 1

      @jsv_schema schema
                  |> Map.put(:"jsv-cast", [Atom.to_string(__MODULE__), @jsv_tag])
                  |> Map.put_new(:"$id", Internal.module_to_uri(__MODULE__))

      @deprecated "use #{inspect(__MODULE__)}.json_schema/0 instead"
      @doc false
      def schema do
        IO.warn(
          "the #{inspect(__MODULE__)}.schema/0 is deprecated and will not be automatically defined in future versions, " <>
            " use #{inspect(__MODULE__)}.json_schema/0 instead"
        )

        json_schema()
      end

      def json_schema do
        @jsv_schema
      end

      @doc false
      def __jsv__(@jsv_tag, data) do
        pairs = JSV.StructSupport.take_keycast(data, @jsv_keycast)
        pairs = Keyword.merge(@default_pairs, pairs)

        {:ok, struct!(@target, pairs)}
      end

      defoverridable schema: 0
    end
  end

  @doc false
  defguard is_valid_tag(tag) when (is_integer(tag) and tag >= 0) or is_binary(tag)

  @doc """
  Enables a casting function in the current module, identified by its function
  name.

  ### Example

  ```elixir
  defmodule MyApp.Cast do
    use JSV.Schema

    defcast :to_integer

    defp to_integer(data) when is_binary(data) do
      case Integer.parse(data) do
        {int, ""} -> {:ok, int}
        _ -> {:error, "invalid"}
      end
    end

    defp to_integer(_) do
      {:error, "invalid"}
    end
  end
  ```

      iex> schema = JSV.Schema.string() |> JSV.Schema.with_cast(["Elixir.MyApp.Cast", "to_integer"])
      iex> root = JSV.build!(schema)
      iex> JSV.validate("1234", root)
      {:ok, 1234}

  See `defcast/3` for more information.
  """
  @doc group: @doc_group
  defmacro defcast(local_fun) when is_atom(local_fun) do
    defcast_local(__CALLER__, Atom.to_string(local_fun), local_fun)
  end

  defmacro defcast(_) do
    bad_cast()
  end

  @doc """
  Enables a casting function in the current module, identified by a custom tag.

  ### Example

  ```elixir
  defmodule MyApp.Cast do
    use JSV.Schema

    defcast "to_integer_if_string", :to_integer

    defp to_integer(data) when is_binary(data) do
      case Integer.parse(data) do
        {int, ""} -> {:ok, int}
        _ -> {:error, "invalid"}
      end
    end

    defp to_integer(_) do
      {:error, "invalid"}
    end
  end
  ```

      iex> schema = JSV.Schema.string() |> JSV.Schema.with_cast(["Elixir.MyApp.Cast", "to_integer_if_string"])
      iex> root = JSV.build!(schema)
      iex> JSV.validate("1234", root)
      {:ok, 1234}

  See `defcast/3` for more information.
  """
  @doc group: @doc_group
  defmacro defcast(tag, local_fun) when is_atom(local_fun) and is_valid_tag(tag) do
    defcast_local(__CALLER__, tag, local_fun)
  end

  defmacro defcast({_, _, _} = call, [{:do, _} | _] = blocks) do
    {fun, _} = Macro.decompose_call(call)
    tag = Atom.to_string(fun)
    defcast_block(__CALLER__, tag, call, blocks)
  end

  defmacro defcast(_, _) do
    bad_cast()
  end

  @doc """
  Defines a casting function in the calling module, and enables it for casting
  data during validation.

  See the [custom cast functions guide](cast-functions.html) to learn more about
  defining your own cast functions.

  This documentation assumes the following module is defined. Note that
  `JSV.Schema` provides several [predefined cast
  functions](JSV.Schema.html#schema-casters), including an [existing atom
  cast](JSV.Schema.html#string_to_existing_atom/0).

  ```elixir
  defmodule MyApp.Cast do
    use JSV.Schema

    defcast to_existing_atom(data) do
      {:ok, String.to_existing_atom(data)}
    rescue
      ArgumentError -> {:error, "bad atom"}
    end

    def accepts_anything(data) do
      {:ok, data}
    end
  end
  ```

  This macro will define the `to_existing_atom/1` function in the calling
  module, and enable it to be referenced in the `jsv-cast` schema custom
  keyword.

      iex> MyApp.Cast.to_existing_atom("erlang")
      {:ok, :erlang}

      iex> MyApp.Cast.to_existing_atom("not an existing atom")
      {:error, "bad atom"}

  It will also define a zero arity function to get the cast information ready to
  be included in a schema:

      iex> MyApp.Cast.to_existing_atom()
      ["Elixir.MyApp.Cast", "to_existing_atom"]

  This is accepted by `JSV.Schema.with_cast/2`:

      iex> JSV.Schema.with_cast(MyApp.Cast.to_existing_atom())
      %JSV.Schema{"jsv-cast": ["Elixir.MyApp.Cast", "to_existing_atom"]}

  With a `jsv-cast` property defined in a schema, data will be cast when the
  schema is validated:

      iex> schema = JSV.Schema.string() |> JSV.Schema.with_cast(MyApp.Cast.to_existing_atom())
      iex> root = JSV.build!(schema)
      iex> JSV.validate("noreply", root)
      {:ok, :noreply}

      iex> schema = JSV.Schema.string() |> JSV.Schema.with_cast(MyApp.Cast.to_existing_atom())
      iex> root = JSV.build!(schema)
      iex> {:error, %JSV.ValidationError{}} = JSV.validate(["Elixir.NonExisting"], root)

  It is not mandatory to use the schema definition helpers. Raw schemas can
  contain cast pointers too:

      iex> schema = %{
      ...>   "type" => "string",
      ...>   "jsv-cast" => ["Elixir.MyApp.Cast", "to_existing_atom"]
      ...> }
      iex> root = JSV.build!(schema)
      iex> JSV.validate("noreply", root)
      {:ok, :noreply}

  Note that for security reasons the cast pointer does not allow to call any
  function from the schema definition. A cast function MUST be enabled by
  `defcast/1`, `defcast/2` or `defcast/3`.

  The `MyApp.Cast` example module above defines a `accepts_anything/1` function,
  but the following schema will fail:

      iex> schema = %{
      ...>   "type" => "string",
      ...>   "jsv-cast" => ["Elixir.MyApp.Cast", "accepts_anything"]
      ...> }
      iex> root = JSV.build!(schema)
      iex> {:error, %JSV.ValidationError{errors: [%JSV.Validator.Error{kind: :"bad-cast"}]}} = JSV.validate("anything", root)

  Finally, you can customize the name present in the `jsv-cast` property by
  using a custom tag:

  ```elixir
  defcast "my_custom_tag", a_function_name(data) do
    # ...
  end
  ```

  Make sure to read the [custom cast functions guide](cast-functions.html)!
  """
  @doc group: @doc_group
  defmacro defcast(tag, fun, block)

  defmacro defcast(tag, {_, _, _} = call, blocks) when is_valid_tag(tag) do
    defcast_block(__CALLER__, tag, call, blocks)
  end

  defmacro defcast(_, _, _) do
    bad_cast()
  end

  defp defcast_block(env, tag, call, [{:do, _} | _] = blocks) do
    {fun, arg} =
      case Macro.decompose_call(call) do
        {:when, [{err_tag, _, _} | _]} ->
          raise ArgumentError, """
          defcast does not support guards

          You may delegate to a local function like so:

            defcast #{inspect(Atom.to_string(err_tag))} :my_custom_cast_fun

            defp #{Macro.to_string(call)} do
              # ...
            end
          """

        {fun, [arg]} ->
          {fun, arg}

        _ ->
          raise ArgumentError, "invalid defcast signature: #{Macro.to_string(call)}"
      end

    mod_str = Atom.to_string(env.module)

    quote do
      def unquote(fun)() do
        [unquote(mod_str), unquote(tag)]
      end

      @doc false
      def __jsv__(unquote(tag), data) do
        unquote(fun)(data)
      end

      @doc false
      def(unquote(fun)(unquote(arg)), unquote(blocks))
    end
  end

  defp defcast_local(_env, tag, local_fun) do
    quote do
      @doc false
      def __jsv__(unquote(tag), xdata) do
        unquote(local_fun)(xdata)
      end
    end
  end

  @spec bad_cast :: no_return()
  defp bad_cast do
    raise ArgumentError, "invalid defcast arguments"
  end

  # ---------------------------------------------------------------------------
  #                              Custom Build API
  # ---------------------------------------------------------------------------

  @doc_group "Custom Build API"

  @doc """
  Initializes a build context for controlled builds.

  See `build/2` for options.
  """
  @spec build_init!([build_opt]) :: build_context()
  @doc group: @doc_group
  debang def build_init!(opts \\ [])

  def build_init!(opts) do
    opts = NimbleOptions.validate!(opts, @build_opts_schema)
    {resolver, opts} = make_resolver(opts)
    builder = make_builder(resolver, opts)
    build_ctx(builder: builder)
  end

  @doc "Adds a schema to the build context."
  @doc group: @doc_group
  @spec build_add!(build_context(), native_schema()) :: {Key.t(), normal_schema(), build_context()}
  debang def build_add!(build_ctx, raw_schema)

  def build_add!(build_ctx(builder: builder) = ctx, raw_schema) do
    raw_schema = ensure_map_schema(raw_schema)
    normal_schema = Schema.normalize(raw_schema)
    key = schema_to_key(normal_schema)
    builder = Builder.add_schema!(builder, key, normal_schema)
    {key, normal_schema, build_ctx(ctx, builder: builder)}
  end

  @doc """
  Builds the given reference or root schema.

  Returns the build context as well as a key, which is a pointer to the built
  schema.
  """
  @doc group: @doc_group
  @spec build_key!(build_context(), Ref.ns() | Ref.t()) :: {Key.t(), build_context()}
  debang def build_key!(build_ctx, ref_or_ns)

  def build_key!(build_ctx(builder: builder, validators: vds) = ctx, ref_or_ns)
      when ref_or_ns == :root
      when is_binary(ref_or_ns)
      when is_struct(ref_or_ns, Ref) do
    key = Key.of(ref_or_ns)

    {new_vds, builder} = Builder.build!(builder, ref_or_ns, vds)
    {key, build_ctx(ctx, builder: builder, validators: new_vds)}
  end

  @doc """
  Returns a root with all the validators from the build context and the given
  `root_key`. That key is used as the default entrypoint for validation when no
  `:key` option is passed to `validate/2`.
  """
  @doc group: @doc_group
  @spec to_root!(build_context, Key.t()) :: Root.t()
  debang def to_root!(build_ctx, root_key)

  def to_root!(build_ctx(validators: vds), root_key) do
    %Root{raw: nil, validators: vds, root_key: root_key}
  end

  defp ensure_map_schema(map) when is_map(map) do
    map
  end

  defp ensure_map_schema(module) when is_atom(module) do
    JSV.Schema.from_module(module)
  end

  defp schema_to_key(raw_schema) do
    case Map.get(raw_schema, "$id", :root) do
      root_ns when is_binary(root_ns) or :root == root_ns -> ^root_ns = Key.of(root_ns)
      other -> raise ArgumentError, "invalid root $id: #{inspect(other)}"
    end
  end

  defp make_resolver(opts) do
    {resolvers, opts} = Keyword.pop!(opts, :resolver)
    {default_meta, opts} = Keyword.pop!(opts, :default_meta)

    resolver =
      resolvers
      |> resolver_chain()
      |> Resolver.chain_of(default_meta)

    {resolver, opts}
  end

  defp make_builder(resolver, opts) do
    Builder.new([{:resolver, resolver} | opts])
  end
end
