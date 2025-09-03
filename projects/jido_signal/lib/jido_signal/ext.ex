defmodule Jido.Signal.Ext do
  @moduledoc """
  Defines the core extension behavior and __using__ macro for Signal extensions.

  Extensions allow Signal to be enhanced with domain-specific functionality while
  maintaining compatibility with the core CloudEvents specification. Each extension
  provides a namespace, schema validation, and serialization support.

  ## Overview

  Extensions are modules that implement the `Jido.Signal.Ext` behavior and use
  the provided `__using__` macro. They automatically register themselves at
  compile time and provide consistent interfaces for attribute conversion.

  ## Creating Extensions

  Use the `__using__` macro to create a new extension:

      defmodule MyApp.Signal.Ext.Auth do
        use Jido.Signal.Ext,
          namespace: "auth",
          schema: [
            user_id: [type: :string, required: true],
            roles: [type: {:list, :string}, default: []],
            expires_at: [type: :pos_integer]
          ]
      end

  ## Extension Registration

  Extensions are automatically registered at compile time via an `@after_compile`
  hook. This enables runtime lookup and validation without requiring manual
  registration steps.

  ## Namespace Rules

  - Must be lowercase strings
  - Should use dots for hierarchical namespaces (e.g., "auth.oauth")
  - Cannot conflict with CloudEvents standard fields
  - Should be unique across your application

  ## Schema Validation

  Extensions use NimbleOptions for schema validation:

  - `:type` - Data type validation
  - `:required` - Required fields
  - `:default` - Default values
  - Custom validators supported

  ## Usage with Signals

  Extensions integrate seamlessly with Signal creation:

      {:ok, signal} = Jido.Signal.new("user.login", %{username: "bob"}, 
        auth: %{user_id: "123", roles: ["user", "admin"]}
      )

      # Extension data is validated and accessible
      assert signal.auth.user_id == "123"
      assert signal.auth.roles == ["user", "admin"]

  ## See Also

  - `Jido.Signal.Ext.Registry` - Extension registration and lookup
  - `Jido.Signal` - Core Signal functionality
  """

  require Logger

  @doc """
  Returns the namespace for this extension.

  The namespace determines the field name used when attaching
  extension data to Signals.
  """
  @callback namespace() :: String.t()

  @doc """
  Returns the NimbleOptions schema for validating extension data.

  The schema defines the structure, types, and validation rules
  for data within this extension's namespace.
  """
  @callback schema() :: keyword()

  @doc """
  Converts extension data to Signal attributes format.

  Takes validated extension data and converts it to the format
  used in Signal attribute maps. The default implementation
  returns the data unchanged.

  ## Parameters
  - `data` - Validated extension data

  ## Returns
  The data in Signal attribute format
  """
  @callback to_attrs(term()) :: term()

  @doc """
  Converts Signal attributes back to extension data format.

  Takes data from Signal attributes and converts it back to the
  extension's expected format. The default implementation
  returns the data unchanged.

  ## Parameters
  - `attrs` - Data from Signal attributes

  ## Returns
  The data in extension format
  """
  @callback from_attrs(term()) :: term()

  @doc """
  Defines a Signal extension module.

  This macro sets up the necessary callbacks and registrations for
  a Signal extension, including schema validation and automatic
  registry integration.

  ## Options

  - `:namespace` - String namespace for the extension (required)
  - `:schema` - NimbleOptions schema for validation (default: [])

  ## Examples

      defmodule MyApp.Signal.Ext.Tracking do
        use Jido.Signal.Ext,
          namespace: "tracking",
          schema: [
            session_id: [type: :string, required: true],
            user_agent: [type: :string],
            ip_address: [type: :string]
          ]
      end

  The extension will be automatically registered and available for use:

      # Look up the extension
      {:ok, ext} = Jido.Signal.Ext.Registry.get("tracking")

      # Use in Signal creation
      {:ok, signal} = Jido.Signal.new("page.view", %{url: "/home"},
        tracking: %{session_id: "abc123", user_agent: "Mozilla/5.0"}
      )
  """
  defmacro __using__(opts) do
    quote location: :keep do
      @behaviour Jido.Signal.Ext

      # Validate and store options at compile time
      opts = unquote(opts)

      if !Keyword.has_key?(opts, :namespace) do
        raise CompileError,
          description: "Extension must specify a :namespace option",
          file: __ENV__.file,
          line: __ENV__.line
      end

      @ext_namespace Keyword.fetch!(opts, :namespace)
      @ext_schema Keyword.get(opts, :schema, [])

      # Validate namespace format
      if !(is_binary(@ext_namespace) and
             String.match?(@ext_namespace, ~r/^[a-z][a-z0-9]*(?:\.[a-z][a-z0-9]*)*$/)) do
        raise CompileError,
          description:
            "Extension namespace must be a lowercase string with optional dots (e.g., 'auth', 'auth.oauth')",
          file: __ENV__.file,
          line: __ENV__.line
      end

      # Validate schema if provided
      if @ext_schema != [] do
        try do
          NimbleOptions.new!(@ext_schema)
        rescue
          e in ArgumentError ->
            reraise CompileError,
                    [
                      description: "Invalid extension schema: #{Exception.message(e)}",
                      file: __ENV__.file,
                      line: __ENV__.line
                    ],
                    __STACKTRACE__
        end
      end

      @impl Jido.Signal.Ext
      def namespace, do: @ext_namespace

      @impl Jido.Signal.Ext
      def schema, do: @ext_schema

      @impl Jido.Signal.Ext
      def to_attrs(data), do: data

      @impl Jido.Signal.Ext
      def from_attrs(attrs), do: attrs

      defoverridable to_attrs: 1, from_attrs: 1

      @doc """
      Validates data according to this extension's schema.

      ## Parameters
      - `data` - The data to validate

      ## Returns
      `{:ok, validated_data}` if valid, `{:error, reason}` otherwise

      ## Examples

          iex> MyExt.validate_data(%{user_id: "123"})
          {:ok, %{user_id: "123"}}

          iex> MyExt.validate_data(%{})
          {:error, "required :user_id option not found"}
      """
      # Compile-time specialization removes unreachable code paths and
      # silences Dialyzer's "pattern can never match" warning.
      if @ext_schema == [] do
        @spec validate_data(term()) :: {:ok, term()}
        def validate_data(data), do: {:ok, data}
      else
        @spec validate_data(term()) :: {:ok, term()} | {:error, String.t()}
        def validate_data(data) do
          data_list = if is_map(data), do: Enum.to_list(data), else: data

          case NimbleOptions.validate(data_list, @ext_schema) do
            {:ok, validated_data} ->
              {:ok, if(is_map(data), do: Map.new(validated_data), else: validated_data)}

            {:error, %NimbleOptions.ValidationError{} = error} ->
              reason =
                Jido.Signal.Error.format_nimble_validation_error(
                  error,
                  "Extension",
                  __MODULE__
                )

              {:error, reason}
          end
        end
      end

      # Auto-register this extension after compilation
      @after_compile __MODULE__

      def __after_compile__(_env, _bytecode) do
        Jido.Signal.Ext.Registry.register(__MODULE__)
      end
    end
  end

  @doc false
  @spec safe_call(module(), atom(), [term()]) :: {:ok, term()} | {:error, any()}
  def safe_call(mod, fun, args) do
    {:ok, apply(mod, fun, args)}
  rescue
    e ->
      Logger.warning(
        "Extension #{inspect(mod)}.#{fun}/#{length(args)} crashed: #{Exception.message(e)}"
      )

      {:error, e}
  catch
    :exit, reason ->
      Logger.warning(
        "Extension #{inspect(mod)}.#{fun}/#{length(args)} exited: #{inspect(reason)}"
      )

      {:error, reason}

    :throw, reason ->
      Logger.warning("Extension #{inspect(mod)}.#{fun}/#{length(args)} threw: #{inspect(reason)}")

      {:error, reason}

    kind, reason ->
      Logger.warning(
        "Extension #{inspect(mod)}.#{fun}/#{length(args)} failed with #{kind}: #{inspect(reason)}"
      )

      {:error, {kind, reason}}
  end

  @doc false
  @spec safe_validate_data(module(), term()) :: {:ok, term()} | {:error, any()}
  def safe_validate_data(ext_mod, data) do
    safe_call(ext_mod, :validate_data, [data])
  end

  @doc false
  @spec safe_to_attrs(module(), term()) :: {:ok, term()} | {:error, any()}
  def safe_to_attrs(ext_mod, data) do
    safe_call(ext_mod, :to_attrs, [data])
  end

  @doc false
  @spec safe_from_attrs(module(), term()) :: {:ok, term()} | {:error, any()}
  def safe_from_attrs(ext_mod, attrs) do
    safe_call(ext_mod, :from_attrs, [attrs])
  end
end
