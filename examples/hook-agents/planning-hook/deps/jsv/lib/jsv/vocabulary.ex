defmodule JSV.Vocabulary do
  alias JSV.Builder
  alias JSV.ErrorFormatter
  alias JSV.Helpers.Math
  alias JSV.Validator

  @moduledoc """
  Behaviour for vocabulary implementation.

  A vocabulary module is used twice during the lifetime of a JSON schema:

  * When building a schema, the vocabulary module is given key/value pairs such
    as `{"type", "integer"}` or `{"properties", map_of_schemas}` and must
    consume or ignore the given keyword, storing custom validation data in an
    accumulator for further use.
  * When validating a schema, the module is called with the data to validate and
    the accumulated validation data to produce a validation result.
  """

  @typedoc """
  Represents the accumulator initially returned by `c:init_validators/1` and
  accepted and returned by `c:handle_keyword/4`.

  This accumulator is then given to `c:finalize_validators/1` and the
  `t:collection/0` type is used from there.
  """
  @type acc :: term

  @typedoc """
  Represents the final form of the collected keywords after the ultimate
  transformation returned by `c:finalize_validators/1`.
  """
  @type collection :: term

  @type pair :: {binary, term}
  @type data :: %{optional(binary) => data} | [data] | binary | boolean | number | nil
  @callback init_validators(keyword) :: acc
  @callback handle_keyword(pair, acc, Builder.t(), raw_schema :: term) :: {acc, Builder.t()} | :ignore
  @callback finalize_validators(acc) :: :ignore | collection
  @callback validate(data, collection, vctx :: Validator.context()) :: Validator.result()
  @callback format_error(atom, %{optional(atom) => term}, data) ::
              String.t()
              | {atom, String.t()}
              | {String.t(), [Validator.Error.t() | ErrorFormatter.error_unit()]}
              | {atom, String.t(), [Validator.Error.t() | ErrorFormatter.error_unit()]}

  @optional_callbacks format_error: 3

  @doc """
  Returns the priority for applyting this module to the data.

  Lower values (close to zero) will be applied first. You can think "order"
  instead of "priority" but several modules can share the same priority value.

  This can be useful to define vocabularies that depend on other vocabularies.
  For instance, the `unevaluatedProperties` keyword needs "properties",
  "patternProperties", "additionalProperties" and "allOf", "oneOf", "anyOf",
  _etc._ to be ran before itself so it can lookup what has been evaluated.

  Modules shipped in this library have priority of 100, 200, etc. up to 900 so
  you can interleave your own vocabularies. Casting values to non-validable
  terms (such as structs or dates) should be done by vocabularies with a
  priority of 1000 and above.
  """
  @callback priority() :: non_neg_integer()

  @doc """
  By using this module you will:

  * Declare that module as a behaviour
  * Import all macros from the module
  * Declare a `priority/0` function if the `:priority` option is provided.
  """
  defmacro __using__(opts) do
    priority_callback =
      case Keyword.fetch(opts, :priority) do
        {:ok, n} when is_integer(n) and n > 0 ->
          quote do
            @impl true
            def priority do
              unquote(n)
            end
          end

        {:ok, :internal} ->
          quote do
            @impl true
            def priority do
              0
            end
          end

        :error ->
          []

        {:ok, other} ->
          raise ArgumentError,
                "expected :priority option to be given as a positive integer literal, got: #{inspect(other)}"
      end

    quote do
      import unquote(__MODULE__)
      @behaviour unquote(__MODULE__)
      import JSV.Builder, only: [unwrap_ok: 1]
      require JSV.Validator
      unquote(priority_callback)
    end
  end

  @doc false
  defmacro todo_format_error do
    quote unquote: false do
      IO.warn("used todo_format_error")

      def format_error(kind, args, _data) do
        keys = Map.keys(args)

        map_format = [
          "%{",
          Enum.map_intersperse(args, ", ", fn {k, _} -> [Atom.to_string(k), ": ", Atom.to_string(k)] end),
          "}"
        ]

        raise """
        TODO! unimplemented error formatting in #{inspect(__MODULE__)}:
        #{__ENV__.file}

        def format_error(#{inspect(kind)}, #{map_format}, _data) do
          "some message"
        end
        """
      end
    end
  end

  @doc """
  An utility macro to ease declare vocabularies with atom keys.

  Defines the `c:handle_keyword/4` callback.

  **Important**

  - The keyword must be given in atom form.
  - The original goal was to allow atom keys and values everywhere. Schemas are
    now converted to binary from before being built.
  - It is still useful to use this macro to the signature of the
    `c:handle_keyword/4` callback can be changed easily without too much
    refactoring.
  - Guards must be placed after the second argument:

        take_keyword :items, items when is_map(items), acc, builder, raw_schema do
          # ...
        end
  """
  defmacro take_keyword(atom_form, bind_value, bind_acc, bind_builder, bind_raw_schema, [{:do, block}])
           when is_atom(atom_form) do
    string_form = Atom.to_string(atom_form)

    {bind_value, when_clause} =
      case bind_value do
        {:when, _, [real_bind, when_clause]} ->
          {real_bind, when_clause}

        _ ->
          {bind_value, true}
      end

    quoted =
      quote generated: true do
        @impl true
        def handle_keyword(
              {unquote(string_form), unquote(bind_value)},
              unquote(bind_acc),
              unquote(bind_builder),
              unquote(bind_raw_schema)
            )
            when unquote(when_clause) do
          unquote(block)
        end
      end

    quoted
  end

  @doc """
  Defines a `c:handle_keyword/4` callback that will return `:ignore` for any
  given value.

  Generally used below `take_keyword/6`:

        take_keyword :items, items when is_map(items), acc, builder, raw_schema do
          # ...
        end

        ignore_any_keyword()
  """
  defmacro ignore_any_keyword do
    quote do
      @impl true
      def handle_keyword(_, _, _, _) do
        :ignore
      end
    end
  end

  @doc """
  Defines a `c:handle_keyword/4` callback that will return `:ignore` for the
  given keyword. The keyword must be given in atom form.

  Generally used below `take_keyword/6`:

        take_keyword :items, items when is_map(items), acc, builder, raw_schema do
          # ...
        end

        ignore_keyword(:additionalItems)
        ignore_keyword(:prefixItems)
  """
  defmacro ignore_keyword(atom_form) when is_atom(atom_form) do
    string_form = Atom.to_string(atom_form)

    quote do
      def handle_keyword({unquote(string_form), _}, _, _, _) do
        :ignore
      end
    end
  end

  @doc """
  Defines a `c:handle_keyword/4` callback that will return the current
  accumulator without changes, but preventing other vocabulary modules with
  lower priority (higher number) to be called with this keyword.

  The keyword must be given in atom form.
  """
  defmacro consume_keyword(atom_form) when is_atom(atom_form) do
    string_form = Atom.to_string(atom_form)

    quote do
      def handle_keyword({unquote(string_form), _}, acc, builder, _) do
        {acc, builder}
      end
    end
  end

  @doc false
  defmacro pass(ast) do
    case ast do
      {:when, _, _} ->
        raise "unsupported guard"

      {fun_name, _, [match_tuple]} ->
        quote do
          def unquote(fun_name)(unquote(match_tuple), data, vctx) do
            {:ok, data, vctx}
          end
        end
    end
  end

  @doc false
  defmacro passp(ast) do
    case ast do
      {:when, _, _} ->
        raise "unsupported guard"

      {fun_name, _, [match_tuple]} ->
        quote do
          defp unquote(fun_name)(unquote(match_tuple), data, vctx) do
            {:ok, data, vctx}
          end
        end
    end
  end

  defmacro with_decimal([{:do, _} | _] = blocks) do
    quote do
      if Code.ensure_loaded?(Decimal), unquote(blocks)
    end
  end

  @doc """
  Casts the given integer to a %Decimal{} struct using `Decimal.from_float/1`
  for floats.
  """
  if Code.ensure_loaded?(Decimal) do
    @spec to_decimal(integer | binary) :: Decimal.t()
    def to_decimal(n) when is_integer(n) do
      Decimal.new(n)
    end

    def to_decimal(n) when is_float(n) do
      Decimal.from_float(n)
    end
  else
    @spec to_decimal(term) :: no_return()
    def to_decimal(_) do
      raise "Decimal dependency missing"
    end
  end

  @doc """
  Gives the sub raw schema to the builder and adds the build result in the list
  accumulator as a 2-tuple with the given `key`.
  """
  @spec take_sub(Builder.path_segment(), JSV.normal_schema(), list, Builder.t()) :: {list, Builder.t()}
  def take_sub(key, sub_raw_schema, acc, builder) when is_list(acc) do
    take_sub(key, key, sub_raw_schema, acc, builder)
  end

  @doc """
  Same as `take_sub/4` but uses a custom `path_segment` to append to the
  `schemaLocation` of the built subschema.
  """
  @spec take_sub(Builder.path_segment(), Builder.path_segment(), JSV.normal_schema(), list, Builder.t()) ::
          {list, Builder.t()}
  def take_sub(key, path_segment, sub_raw_schema, acc, builder) when is_list(acc) do
    {subvalidators, builder} = Builder.build_sub!(sub_raw_schema, [path_segment], builder)
    {[{key, subvalidators} | acc], builder}
  end

  @doc """
  Adds the given integer to the list accumulator as a 2-tuple with the given
  `key`.

  Fails if the value is not an integer. Floats with zero-fractional (as `123.0`)
  will be accepted and converted to integer, as the JSON Schema spec dictates.
  """
  @spec take_integer(Builder.path_segment(), integer | term, list, Builder.t()) :: {list, Builder.t()}
  def take_integer(key, n, acc, builder) when is_list(acc) do
    case force_integer(n) do
      {:ok, n} -> {[{key, n} | acc], builder}
      :error -> Builder.fail(builder, {:invalid_integer, n}, :take_integer)
    end
  end

  defp force_integer(n) when is_integer(n) do
    {:ok, n}
  end

  defp force_integer(n) when is_float(n) do
    if Math.fractional_is_zero?(n) do
      {:ok, Math.trunc(n)}
    else
      :error
    end
  end

  defp force_integer(_) do
    :error
  end

  @doc """
  Adds the given integer to the list accumulator as a 2-tuple with the given
  `key`.

  Fails if the value is not a number.
  """
  @spec take_number(Builder.path_segment(), number | term, list, Builder.t()) :: {list, Builder.t()}
  def take_number(key, n, acc, builder) when is_list(acc) do
    case is_number(n) do
      true -> {[{key, n} | acc], builder}
      false -> Builder.fail(builder, {:invalid_number, n}, :take_number)
    end
  end
end
