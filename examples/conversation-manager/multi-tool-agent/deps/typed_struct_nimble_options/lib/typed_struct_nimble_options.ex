defmodule TypedStructNimbleOptions do
  use TypedStruct.Plugin

  @options_schema NimbleOptions.new!(
                    ctor: [
                      type: {:or, [:atom, nil]},
                      default: :new,
                      doc: """
                      Name of the non-bang constructor function.
                      `nil` disables constructor generation.
                      """
                    ],
                    ctor!: [
                      type: {:or, [:atom, nil]},
                      default: :new!,
                      doc: """
                      Name of the bang constructor function.
                      `nil` disables bang constructor generation.
                      """
                    ],
                    docs: [
                      type: {:or, [:atom, nil]},
                      default: :field_docs,
                      doc: """
                      Name of the functions that return the NimbleOptions docs for the struct.
                      `nil` disables docs functions generation.
                      """
                    ],
                    otp_app: [
                      type: :atom,
                      doc: """
                      Name of the OTP application using TypedStructNimbleOptions.
                      This is used to fetch global options for the TypedStructNimbleOptions.
                      Defaults to `Application.get_application(__CALLER__.module)`.
                      """
                    ],
                    append_moduledoc_header: [
                      type: {:or, [:string, nil]},
                      default: "\n## Fields",
                      doc: """
                      Whether to append the generated docs to the @moduledoc.
                      The docs are appended with the header specified in this option.
                      Docs are appended only if the header is not nil.
                      """
                    ],
                    warn_unknown_types?: [
                      type: :boolean,
                      default: true,
                      doc: """
                      Whether to warn when an unknown type is encountered.
                      """
                    ]
                  )

  @moduledoc """
  Merge typed_struct and nimble_options to form a documented, validated struct type.

  ## Supported options
  #{NimbleOptions.docs(@options_schema)}
  """

  @impl TypedStruct.Plugin
  defmacro init(opts) do
    otp_app =
      Keyword.get_lazy(opts, :otp_app, fn -> Application.get_application(__CALLER__.module) end)

    global_opts =
      if is_nil(otp_app), do: [], else: Application.get_env(otp_app, TypedStructNimbleOptions, [])

    opts =
      global_opts
      |> Config.Reader.merge(opts)
      |> Map.new()
      |> NimbleOptions.validate!(@options_schema)

    Module.register_attribute(__CALLER__.module, attr_name(:fields), accumulate: true)
    Module.put_attribute(__CALLER__.module, attr_name(:opts), opts)

    quote do
    end
  end

  @impl TypedStruct.Plugin
  def field(name, type, field_opts, env) do
    opts = Module.get_attribute(env.module, attr_name(:opts))

    validation_type =
      Keyword.get_lazy(field_opts, :validation_type, fn ->
        type = Macro.postwalk(type, &Macro.expand(&1, env))
        derive_validation_type(name, type, opts, env)
      end)

    validation_type =
      with {:nested_struct, struct, constructor} <- validation_type,
           do: {:custom, __MODULE__, :_nested_struct, [struct, constructor]}

    derived_opts = [
      required: required?(name, field_opts, env.module),
      type_spec: type,
      type: validation_type
    ]

    nimble_opts =
      field_opts
      |> Keyword.take([
        :required,
        :default,
        :keys,
        :deprecated,
        :doc,
        :subsection,
        :type_doc,
        :type_spec
      ])
      |> then(&Keyword.merge(derived_opts, &1))

    Module.put_attribute(env.module, attr_name(:fields), {name, nimble_opts})

    quote do
    end
  end

  @impl TypedStruct.Plugin
  def after_definition(_opts) do
    quote do
      require TypedStructNimbleOptions
      TypedStructNimbleOptions.after_definition()
    end
  end

  defmacro after_definition do
    opts = Module.delete_attribute(__CALLER__.module, attr_name(:opts))

    schema =
      __CALLER__.module
      |> Module.get_attribute(attr_name(:fields))
      |> Enum.reverse()
      |> NimbleOptions.new!()

    Module.put_attribute(__CALLER__.module, attr_name(:schema), schema)

    append_moduledoc(schema, opts, __CALLER__)

    {:__block__, [],
     [
       default_fn(opts.ctor),
       ctor_fn(opts.ctor),
       default_fn(opts.ctor!),
       ctor_bang_fn(opts.ctor!),
       docs_fn(opts.docs)
     ]}
  end

  def _nested_struct(attrs, struct, constructor) do
    with {:error, reason} <- apply(struct, constructor, [attrs]),
         do: {:error, Exception.message(reason)}
  end

  defp append_moduledoc(schema, %{append_moduledoc_header: <<header::binary>>}, env) do
    field_docs = NimbleOptions.docs(schema)
    {line, doc} = with nil <- Module.delete_attribute(env.module, :moduledoc), do: {0, ""}
    doc = "#{doc}\n#{header}\n#{field_docs}"
    Module.put_attribute(env.module, :moduledoc, {line, doc})
  end

  defp append_moduledoc(_schema, _opts, _env), do: nil

  defp ctor_fn(nil), do: nil

  defp ctor_fn(fname) do
    quote do
      @spec unquote(fname)(struct() | Enumerable.t()) ::
              {:ok, __MODULE__.t()} | {:error, Exception.t()}
      def unquote(fname)(%_{} = struct), do: unquote(fname)(Map.from_struct(struct))

      def unquote(fname)(attrs) do
        with {:ok, attrs} <- NimbleOptions.validate(attrs, unquote(attr(:schema))),
             do: {:ok, struct!(__MODULE__, attrs)}
      rescue
        e -> {:error, e}
      end
    end
  end

  defp ctor_bang_fn(nil), do: nil

  defp ctor_bang_fn(fname) do
    quote do
      @spec unquote(fname)(struct() | Enumerable.t()) :: __MODULE__.t()
      def unquote(fname)(%_{} = struct), do: struct |> Map.from_struct() |> unquote(fname)()

      def unquote(fname)(attrs) do
        attrs = NimbleOptions.validate!(attrs, unquote(attr(:schema)))
        struct!(__MODULE__, attrs)
      end
    end
  end

  defp docs_fn(nil), do: nil

  defp docs_fn(fname) do
    quote do
      @spec unquote(fname)(Keyword.t()) :: String.t()
      def unquote(fname)(options \\ []), do: NimbleOptions.docs(unquote(attr(:schema)), options)
    end
  end

  defp default_fn(nil), do: nil

  defp default_fn(fname) do
    quote do
      unless Enum.any?(unquote(attr(:fields)), fn {_name, opts} -> opts[:required] end) do
        def unquote(fname)(), do: unquote(fname)([])
      end
    end
  end

  defp attr_name(name), do: :"typed_struct_nimble_options__#{name}"

  defp attr(name), do: quote(do: @unquote({attr_name(name), [], nil}))

  defp required?(name, opts, module) do
    has_default? = Keyword.has_key?(opts, :default)
    enforce? = name in Module.get_attribute(module, :enforce_keys, [])
    not has_default? and enforce?
  end

  defp derive_validation_type(name, type, opts, env) do
    try do
      do_derive_validation_type(type)
    catch
      {:unknown_node, node} ->
        if Map.get(opts, :warn_unknown_types?, true) do
          IO.warn("""
          Cannot automatically derive validation_type; falling back to `:any`
            struct: `#{env.module}`
            field: `#{name}`
            type: `#{Macro.to_string(type)}`
            reason: unsupported type `#{Macro.to_string(node)}`

            To suppress this warning, add `validation_type: :any` option to \
          the `field :#{name}` definition, or set \
          `warn_unknown_types?: false` in the `use TypedStructNimbleOptions` \
          options.
            See https://hexdocs.pm/nimble_options/NimbleOptions.html#module-types \
          for the list of supported validation types.
          """)
        end

        :any
    end
  end

  @one_to_one_type_mappings [
    :atom,
    :boolean,
    :integer,
    :non_neg_integer,
    :pos_integer,
    :float,
    :timeout,
    :pid,
    :reference,
    :mfa,
    :any
  ]

  defp do_derive_validation_type({atom, meta, context}) when is_atom(atom) and is_atom(context),
    do: do_derive_validation_type({atom, meta, []})

  defp do_derive_validation_type({:map, _, []}), do: {:map, :any, :any}
  defp do_derive_validation_type({:%{}, _, []}), do: {:map, :any, :any}

  defp do_derive_validation_type({:%{}, _, [{{:optional, _, [key]}, value}]}),
    do: {:map, do_derive_validation_type(key), do_derive_validation_type(value)}

  defp do_derive_validation_type({:%{}, _, [{key, value}]}),
    do: {:map, do_derive_validation_type(key), do_derive_validation_type(value)}

  defp do_derive_validation_type({:list, _, []}), do: {:list, :any}
  defp do_derive_validation_type({:list, _, [type]}), do: {:list, do_derive_validation_type(type)}
  defp do_derive_validation_type([type]), do: {:list, do_derive_validation_type(type)}

  defp do_derive_validation_type({typea, typeb}),
    do: {:tuple, [do_derive_validation_type(typea), do_derive_validation_type(typeb)]}

  defp do_derive_validation_type({:{}, _, types}),
    do: {:tuple, Enum.map(types, &do_derive_validation_type/1)}

  defp do_derive_validation_type({{:., _, [String, :t]}, _, []}), do: :string
  defp do_derive_validation_type(nil), do: nil
  defp do_derive_validation_type({:term, _, []}), do: :any
  defp do_derive_validation_type({type, _, []}) when type in @one_to_one_type_mappings, do: type
  defp do_derive_validation_type(other), do: throw({:unknown_node, other})
end
