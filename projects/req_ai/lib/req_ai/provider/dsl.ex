defmodule ReqAI.Provider.DSL do
  @moduledoc """
  DSL for generating AI provider adapter implementations with unified behavior.

  This module provides the `__using__/1` macro that generates the boilerplate
  code for AI provider modules, implementing the unified ReqAI.Provider.Adapter.

  ## Simple Usage (implement directly in provider)

      defmodule MyProvider do
        use ReqAI.Provider.DSL,
          id: :my_provider,
          base_url: "https://api.example.com",
          auth: {:header, "authorization", :plain}

        @impl true
        def build_request(messages, _provider_opts, request_opts) do
          # Implementation here
        end

        @impl true  
        def parse_response(response, _provider_opts, _request_opts) do
          # Implementation here
        end
      end

  ## Complex Usage (with separate builder/parser modules)

      defmodule MyProvider do
        use ReqAI.Provider.DSL,
          id: :my_provider,
          base_url: "https://api.example.com",
          auth: {:header, "authorization", :plain},
          builder: MyProvider.Builder,
          parser: MyProvider.Parser
      end

  ## Options

    - `:id` - Provider identifier atom (required)
    - `:base_url` - Base URL for the provider API (required)
    - `:auth` - Auth configuration tuple (required)
    - `:builder` - Module that implements `build_request/3` (defaults to provider module)
    - `:parser` - Module that implements `parse_response/3` (defaults to provider module)
  """

  defmacro __using__(opts) do
    id = Keyword.get(opts, :id)
    base_url = Keyword.get(opts, :base_url)
    auth = Keyword.get(opts, :auth)
    default_model = Keyword.get(opts, :default_model)
    default_temperature = Keyword.get(opts, :default_temperature)
    default_max_tokens = Keyword.get(opts, :default_max_tokens)
    metadata_file = Keyword.get(opts, :metadata)

    unless id do
      raise ArgumentError, "ReqAI.Provider.DSL requires :id option"
    end

    unless base_url do
      raise ArgumentError, "ReqAI.Provider.DSL requires :base_url option"
    end

    unless auth do
      raise ArgumentError, "ReqAI.Provider.DSL requires :auth option"
    end

    # Calculate JSON path - prefer /priv/models_dev by default
    json_path =
      if metadata_file do
        Path.join(:code.priv_dir(:req_ai), "models_dev/#{metadata_file}")
      end

    quote bind_quoted: [
            id: id,
            base_url: base_url,
            auth: auth,
            default_model: default_model,
            default_temperature: default_temperature,
            default_max_tokens: default_max_tokens,
            metadata_file: metadata_file,
            json_path: json_path
          ] do
      @behaviour ReqAI.Provider.Adapter
      @behaviour ReqAI.Provider
      @after_compile {ReqAI.Provider.Registry, :auto_register}

      # Mark as external resource for recompilation
      if json_path, do: @external_resource(json_path)

      {provider_meta, models_map} =
        cond do
          json_path && File.exists?(json_path) ->
            json_path
            |> File.read!()
            |> Jason.decode!()
            |> then(fn data ->
              prov = Map.get(data, "provider", %{})
              models_data = Map.get(data, "models", [])

              models =
                Map.new(models_data, fn model_data ->
                  model =
                    ReqAI.Model.new(
                      id,
                      model_data["id"],
                      modalities: ReqAI.Provider.DSL.parse_modalities(model_data["modalities"]),
                      capabilities: ReqAI.Provider.DSL.parse_capabilities(model_data),
                      cost: ReqAI.Provider.DSL.parse_cost(model_data["cost"]),
                      limit: ReqAI.Provider.DSL.parse_limit(model_data["limit"])
                    )

                  {model_data["id"], model}
                end)

              {prov, models}
            end)

          metadata_file ->
            require Logger

            Logger.warning(
              "ReqAI provider #{inspect(__MODULE__)}: JSON #{metadata_file} not found"
            )

            {%{}, %{}}

          true ->
            {%{}, %{}}
        end

      @provider_id id
      @base_url base_url
      @auth auth
      @models_map models_map
      @default_model default_model
      @default_temperature default_temperature
      @default_max_tokens default_max_tokens

      @impl ReqAI.Provider.Adapter
      def spec do
        spec_opts = [
          id: @provider_id,
          base_url: @base_url,
          auth: @auth,
          models: @models_map
        ]

        spec_opts =
          if @default_model,
            do: Keyword.put(spec_opts, :default_model, @default_model),
            else: spec_opts

        spec_opts =
          if @default_temperature,
            do: Keyword.put(spec_opts, :default_temperature, @default_temperature),
            else: spec_opts

        spec_opts =
          if @default_max_tokens,
            do: Keyword.put(spec_opts, :default_max_tokens, @default_max_tokens),
            else: spec_opts

        ReqAI.Provider.Spec.new(spec_opts)
      end

      @impl ReqAI.Provider
      def provider_info do
        spec = spec()
        ReqAI.Provider.new(spec.id, spec.id |> to_string() |> String.capitalize(), spec.base_url)
      end

      @impl ReqAI.Provider
      def generate_text(model, messages, opts \\ []) do
        with {:ok, request} <- build_request(messages, [], opts),
             request_with_spec <- ReqAI.HTTP.with_provider_spec(request, spec()),
             {:ok, response} <- ReqAI.HTTP.send(request_with_spec, opts),
             {:ok, parsed} <- parse_response(response, [], opts) do
          {:ok, parsed}
        end
      end

      @impl ReqAI.Provider
      def stream_text(model, messages, opts \\ []) do
        stream_opts = Keyword.put(opts, :stream?, true)

        with {:ok, request} <- build_request(messages, [], stream_opts),
             request_with_spec <- ReqAI.HTTP.with_provider_spec(request, spec()),
             {:ok, response} <- ReqAI.HTTP.send(request_with_spec, stream_opts) do
          {:ok, response}
        end
      end

      # Helper functions for accessing models
      @doc "Returns all models loaded from JSON metadata."
      def models, do: @models_map

      @doc "Returns a specific model by ID."
      def get_model(model_id), do: Map.get(@models_map, model_id)

      # Allow overriding for providers that implement logic directly
      defoverridable generate_text: 3, stream_text: 3
    end
  end

  # Helper functions for parsing JSON data - public so they can be called from the macro
  @doc false
  def parse_modalities(nil), do: nil

  def parse_modalities(%{"input" => input, "output" => output}) do
    %{
      input: Enum.map(input, &convert_to_atom/1),
      output: Enum.map(output, &convert_to_atom/1)
    }
  end

  def parse_modalities(_), do: nil

  @doc false
  def parse_capabilities(model_data) do
    %{
      reasoning?: Map.get(model_data, "reasoning", false),
      tool_call?: Map.get(model_data, "tool_call", false),
      supports_temperature?: Map.get(model_data, "supports_temperature", true)
    }
  end

  @doc false
  def parse_cost(nil), do: nil

  def parse_cost(%{"input" => input, "output" => output}) do
    %{input: input, output: output}
  end

  def parse_cost(_), do: nil

  @doc false
  def parse_limit(nil), do: nil

  def parse_limit(%{"context" => context, "output" => output}) do
    %{context: context, output: output}
  end

  def parse_limit(_), do: nil

  @doc false
  def convert_to_atom(str) when is_binary(str) do
    try do
      String.to_existing_atom(str)
    rescue
      ArgumentError ->
        # Return string as-is rather than creating new atoms
        # This prevents DoS attacks via atom table exhaustion
        str
    end
  end

  def convert_to_atom(atom) when is_atom(atom), do: atom
end
