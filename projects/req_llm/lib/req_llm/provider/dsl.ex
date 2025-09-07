defmodule ReqLLM.Provider.DSL do
  @moduledoc """
  DSL for generating AI provider adapter implementations with unified behavior.

  This module provides the `__using__/1` macro that generates the boilerplate
  code for AI provider modules, implementing the unified ReqLLM.Provider.Adapter.

  ## Simple Usage (implement directly in provider)

      defmodule MyProvider do
        use ReqLLM.Provider.DSL,
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
        use ReqLLM.Provider.DSL,
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
      raise ArgumentError, "ReqLLM.Provider.DSL requires :id option"
    end

    unless base_url do
      raise ArgumentError, "ReqLLM.Provider.DSL requires :base_url option"
    end

    unless auth do
      raise ArgumentError, "ReqLLM.Provider.DSL requires :auth option"
    end

    # Calculate JSON path - prefer /priv/models_dev by default
    json_path =
      if metadata_file do
        Path.join(:code.priv_dir(:req_llm), "models_dev/#{metadata_file}")
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
      @behaviour ReqLLM.Provider.Adapter
      @after_compile {ReqLLM.Provider.Registry, :auto_register}

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
                    ReqLLM.Model.new(
                      id,
                      model_data["id"],
                      modalities: ReqLLM.Provider.DSL.parse_modalities(model_data["modalities"]),
                      capabilities: ReqLLM.Provider.DSL.parse_capabilities(model_data),
                      cost: ReqLLM.Provider.DSL.parse_cost(model_data["cost"]),
                      limit: ReqLLM.Provider.DSL.parse_limit(model_data["limit"])
                    )

                  {model_data["id"], model}
                end)

              {prov, models}
            end)

          metadata_file ->
            require Logger

            Logger.warning(
              "ReqLLM provider #{inspect(__MODULE__)}: JSON #{metadata_file} not found"
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

      @impl ReqLLM.Provider.Adapter
      def spec do
        spec_opts = [
          id: @provider_id,
          base_url: @base_url,
          auth: @auth,
          models: @models_map
        ]

        spec_opts =
          unquote(
            if default_model != nil do
              quote do
                Keyword.put(spec_opts, :default_model, @default_model)
              end
            else
              quote do
                spec_opts
              end
            end
          )

        spec_opts =
          unquote(
            if default_temperature != nil do
              quote do
                Keyword.put(spec_opts, :default_temperature, @default_temperature)
              end
            else
              quote do
                spec_opts
              end
            end
          )

        spec_opts =
          unquote(
            if default_max_tokens != nil do
              quote do
                Keyword.put(spec_opts, :default_max_tokens, @default_max_tokens)
              end
            else
              quote do
                spec_opts
              end
            end
          )

        ReqLLM.Provider.Spec.new(spec_opts)
      end

      @impl ReqLLM.Provider.Adapter
      def provider_info do
        spec = spec()
        ReqLLM.Provider.new(spec.id, spec.id |> to_string() |> String.capitalize(), spec.base_url)
      end

      @impl ReqLLM.Provider.Adapter
      def generate_text(model, messages, opts \\ []) do
        # Pass model through to HTTP layer for token usage tracking
        http_opts = Keyword.put(opts, :model, model)
        # Pass model to build_request through opts
        build_opts = Keyword.put(opts, :model, model)

        with {:ok, request} <- build_request(messages, [], build_opts),
             request_with_spec <- ReqLLM.HTTP.with_provider_spec(request, spec()),
             {:ok, response} <- ReqLLM.HTTP.send(request_with_spec, http_opts),
             {:ok, parsed} <- parse_response(response, [], opts) do
          # Return full response if :return_response option is set, otherwise just parsed text
          if Keyword.get(opts, :return_response, false) do
            {:ok, %{response | body: parsed}}
          else
            {:ok, parsed}
          end
        end
      end

      @impl ReqLLM.Provider.Adapter
      def stream_text(model, messages, opts \\ []) do
        stream_opts = Keyword.put(opts, :stream?, true)
        # Pass model through to HTTP layer for token usage tracking
        http_opts = Keyword.put(stream_opts, :model, model)
        # Pass model to build_request through opts
        build_opts = Keyword.put(stream_opts, :model, model)

        with {:ok, request} <- build_request(messages, [], build_opts),
             request_with_spec <- ReqLLM.HTTP.with_provider_spec(request, spec()),
             {:ok, response} <- ReqLLM.HTTP.send(request_with_spec, http_opts) do
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
