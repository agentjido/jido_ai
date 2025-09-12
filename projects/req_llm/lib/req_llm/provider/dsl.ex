defmodule ReqLLM.Provider.DSL do
  @moduledoc """
  Domain-Specific Language for defining ReqLLM providers.

  This macro simplifies provider creation by automatically handling:
  - Plugin behaviour implementation
  - Metadata loading from JSON files
  - Provider registry registration
  - Default configuration setup

  ## Usage

      defmodule MyProvider do
      use ReqLLM.Provider.DSL,
      id: :my_provider,
      base_url: "https://api.example.com/v1",
      metadata: "priv/models_dev/my_provider.json"

        def attach(request, model) do
          # Provider-specific request configuration
        end

        def parse(response, model) do
          # Provider-specific response parsing
        end
      end

  ## Options

    * `:id` - Unique provider identifier (required atom)
    * `:base_url` - Default API base URL (required string)
    * `:metadata` - Path to JSON metadata file (optional string)

  ## Generated Code

  The DSL automatically generates:

  1. **Plugin Behaviour**: `use Req.Plugin`
  2. **Default Base URL**: `def default_base_url(), do: "https://api.example.com/v1"`
  3. **Registry Registration**: Calls `ReqLLM.Provider.Registry.register/3`
  4. **Metadata Loading**: Loads and parses JSON metadata at compile time

  ## Metadata Files

  Metadata files should contain JSON with model information:

      {
        "models": [
          {
            "id": "my-model-1",
            "context_length": 8192,
            "capabilities": ["text_generation"],
            "pricing": {
              "input": 0.001,
              "output": 0.002
            }
          }
        ],
        "capabilities": ["text_generation", "embeddings"],
        "documentation": "https://api.example.com/docs"
      }

  ## Example Implementation

      defmodule ReqLLM.Providers.Example do
      use ReqLLM.Provider.DSL,
      id: :example,
      base_url: "https://api.example.com/v1",
      metadata: "priv/models_dev/example.json"

        def attach(request, %ReqLLM.Model{} = model) do
          api_key = ReqLLM.get_key(:example_api_key)

          request
          |> Req.Request.put_header("authorization", "Bearer \#{api_key}")
          |> Req.Request.put_header("content-type", "application/json")
          |> Req.Request.put_base_url(default_base_url())
          |> Req.Request.put_body(%{
            model: model.model,
            messages: format_messages(model.context),
            temperature: model.temperature
          })
        end

        def parse(response, %ReqLLM.Model{} = model) do
          case response.body do
            %{"content" => content} ->
              {:ok, content}
            %{"error" => error} ->
              {:error, ReqLLM.Error.api_error(error)}
            _ ->
              {:error, ReqLLM.Error.parse_error("Invalid response format")}
          end
        end

        # Private helper functions...
      end

  """

  @doc """
  Sigil for defining lists of atoms from space-separated words.

  ## Examples

      ~a[temperature max_tokens top_p]  # => [:temperature, :max_tokens, :top_p]
  """

  # defmacro sigil_a({:<<>>, _, [string]}, _mods) do
  #   list =
  #     string
  #     |> String.split(~r/\s+/, trim: true)
  #     |> Enum.map(&String.to_atom/1)

  #   Macro.escape(list)
  # end

  defmacro __using__(opts) do
    # Validate required options
    id = Keyword.fetch!(opts, :id)
    base_url = Keyword.fetch!(opts, :base_url)
    metadata_path = Keyword.get(opts, :metadata)
    provider_options = Keyword.get(opts, :provider_options)
    provider_defaults = Keyword.get(opts, :provider_defaults, [])

    unless is_atom(id) do
      raise ArgumentError, "Provider :id must be an atom, got: #{inspect(id)}"
    end

    unless is_binary(base_url) do
      raise ArgumentError, "Provider :base_url must be a string, got: #{inspect(base_url)}"
    end

    quote do
      # Implement Req plugin pattern (no formal behaviour needed)

      # Store configuration for use in callbacks
      @provider_id unquote(id)
      @base_url unquote(base_url)
      @metadata_path unquote(metadata_path)
      @supported_provider_options unquote(provider_options)
      @default_provider_opts unquote(provider_defaults)

      # Set external resource if metadata file exists
      if @metadata_path do
        @external_resource @metadata_path
      end

      # Register provider before compilation completes
      @before_compile ReqLLM.Provider.DSL

      # Implement default_base_url function
      def default_base_url do
        @base_url
      end

      defoverridable default_base_url: 0
    end
  end

  defmacro __before_compile__(env) do
    # Get the compiled module's attributes
    provider_id = Module.get_attribute(env.module, :provider_id)
    metadata_path = Module.get_attribute(env.module, :metadata_path)
    supported_provider_options = Module.get_attribute(env.module, :supported_provider_options)
    default_provider_opts = Module.get_attribute(env.module, :default_provider_opts)

    # Load metadata if file exists
    metadata = load_metadata(metadata_path)

    # Default to all generation keys if not specified
    final_provider_options =
      supported_provider_options ||
        quote(do: ReqLLM.Provider.Options.all_generation_keys())

    quote do
      # Store metadata as module attribute
      @req_llm_metadata unquote(Macro.escape(metadata))

      # Optional helpers for accessing provider info
      def metadata, do: @req_llm_metadata
      def provider_id, do: unquote(provider_id)

      # Provider option helpers
      def supported_provider_options, do: unquote(final_provider_options)
      def default_provider_opts, do: unquote(default_provider_opts || [])

      def provider_schema,
        do: ReqLLM.Provider.Options.generation_subset_schema(supported_provider_options())
    end
  end

  # Private helper to load metadata at compile time
  defp load_metadata(nil), do: %{}

  defp load_metadata(path) when is_binary(path) do
    full_path = Path.expand(path)

    if File.exists?(full_path) do
      case File.read(full_path) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, data} ->
              # Convert string keys to atom keys for easier access
              atomize_keys(data)

            {:error, error} ->
              IO.warn("Failed to parse JSON metadata from #{path}: #{inspect(error)}")
              %{}
          end

        {:error, error} ->
          IO.warn("Failed to read metadata file #{path}: #{inspect(error)}")
          %{}
      end
    else
      IO.warn("Metadata file not found: #{path}")
      %{}
    end
  end

  # Helper to recursively convert string keys to atoms (for known keys only)
  defp atomize_keys(data) when is_map(data) do
    data
    |> Enum.map(fn
      {"models", value} -> {:models, atomize_keys(value)}
      {"capabilities", value} -> {:capabilities, value}
      {"pricing", value} -> {:pricing, atomize_keys(value)}
      {"context_length", value} -> {:context_length, value}
      {"id", value} -> {:id, value}
      {"input", value} -> {:input, value}
      {"output", value} -> {:output, value}
      {key, value} -> {key, atomize_keys(value)}
    end)
    |> Map.new()
  end

  defp atomize_keys(data) when is_list(data) do
    Enum.map(data, &atomize_keys/1)
  end

  defp atomize_keys(data), do: data
end
