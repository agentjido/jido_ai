defmodule Jido.AI.Provider.Macro do
  @moduledoc """
  Provides the `__using__` macro for creating AI provider modules.

  This module handles compile-time loading of provider metadata and provides
  default implementations for all provider callbacks.
  """

  alias Jido.AI.Error.SchemaValidation
  alias Jido.AI.ObjectSchema
  alias Jido.AI.Provider.{Request, Response, Util}
  alias Jido.AI.{CostCalculator, Error, Message, Model, Provider}

  require Logger

  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Jido.AI.Provider.Behaviour

      alias Jido.AI.{Model, Provider}

      require Logger

      json_filename =
        opts[:json] || raise ArgumentError, "expected :json option with JSON filename"

      base_url = opts[:base_url] || raise ArgumentError, "expected :base_url option"

      # Build full JSON path
      json_path = Path.join(:code.priv_dir(:jido_ai), "models_dev/#{json_filename}")

      # Mark file as external resource for recompilation
      @external_resource json_path

      # Load JSON data at compile time
      {provider_meta, models_map} =
        case File.read(json_path) do
          {:ok, json_content} ->
            data = Jason.decode!(json_content)
            provider_data = data["provider"] || %{}

            models =
              data
              |> Map.get("models", [])
              |> Map.new(fn model -> {model["id"], model} end)

            {provider_data, models}

          {:error, reason} ->
            Logger.warning("Failed to load provider JSON #{json_path}: #{inspect(reason)}")
            {%{}, %{}}
        end

      # Extract provider metadata with option overrides
      id_atom =
        String.to_atom(opts[:id] || provider_meta["id"] || raise(ArgumentError, "provider id not found"))

      name = opts[:name] || provider_meta["name"] || Atom.to_string(id_atom) |> Macro.camelize()
      env_vars = opts[:env] || provider_meta["env"] || []
      env_atoms = env_vars |> Enum.map(&String.to_atom/1)

      # Embed provider info and base URL as module attributes
      @provider_info %Provider{
        id: id_atom,
        name: name,
        base_url: base_url,
        doc: "",
        env: env_atoms,
        models: models_map
      }
      @base_url base_url

      # Implement callbacks using compile-time data
      @doc "Returns provider information loaded from compile-time metadata."
      @impl true
      @spec provider_info() :: Provider.t()
      def provider_info, do: @provider_info

      @doc "Returns the base API URL for this provider."
      @impl true
      @spec api_url() :: String.t()
      def api_url, do: @base_url

      # Default to not supporting JSON mode - providers can override
      @doc "Returns whether this provider supports JSON mode."
      @impl true
      @spec supports_json_mode?() :: false
      def supports_json_mode?, do: false

      # Default to OpenAI-style options - providers can override
      @doc "Returns the default chat completion options for this provider."
      @impl true
      @spec chat_completion_opts() :: [
              :frequency_penalty
              | :max_completion_tokens
              | :max_tokens
              | :messages
              | :model
              | :n
              | :presence_penalty
              | :response_format
              | :seed
              | :stop
              | :temperature
              | :top_p
              | :user,
              ...
            ]
      def chat_completion_opts, do: Util.Options.default()

      # Default to OpenAI stream format - providers can override
      @doc "Returns the stream event type for this provider."
      @impl true
      @spec stream_event_type() :: :openai
      def stream_event_type, do: :openai

      # Provide default implementation
      @doc "Generates text using the default implementation."
      @impl true
      @spec generate_text(Model.t(), String.t() | [Message.t()], keyword()) :: {:ok, String.t()} | {:error, Error.t()}
      def generate_text(%Model{} = model, prompt, opts \\ []) do
        Jido.AI.Provider.Macro.default_generate_text(__MODULE__, model, prompt, opts)
      end

      @doc "Streams text using the default implementation."
      @impl true
      @spec stream_text(Model.t(), String.t() | [Message.t()], keyword()) :: {:ok, Enumerable.t()} | {:error, Error.t()}
      def stream_text(%Model{} = model, prompt, opts \\ []) do
        Jido.AI.Provider.Macro.default_stream_text(__MODULE__, model, prompt, opts)
      end

      @doc "Generates structured objects using the default implementation."
      @impl true
      @spec generate_object(Model.t(), String.t() | [Message.t()], map() | keyword(), keyword()) ::
              {:ok, map()} | {:error, Error.t()}
      def generate_object(%Model{} = model, prompt, schema, opts \\ []) do
        Jido.AI.Provider.Macro.default_generate_object(__MODULE__, model, prompt, schema, opts)
      end

      @doc "Streams structured objects using the default implementation."
      @impl true
      @spec stream_object(Model.t(), String.t() | [Message.t()], map() | keyword(), keyword()) ::
              {:ok, Enumerable.t()} | {:error, Error.t()}
      def stream_object(%Model{} = model, prompt, schema, opts \\ []) do
        Jido.AI.Provider.Macro.default_stream_object(__MODULE__, model, prompt, schema, opts)
      end

      # Make callbacks overridable
      defoverridable generate_text: 3,
                     stream_text: 3,
                     generate_object: 4,
                     stream_object: 4,
                     supports_json_mode?: 0,
                     chat_completion_opts: 0,
                     stream_event_type: 0
    end
  end

  @doc """
  Default implementation for generating text using OpenAI-style chat completions.
  """
  @spec default_generate_text(module(), Model.t(), String.t() | [Message.t()], keyword()) ::
          {:ok, String.t()} | {:error, Error.t()}
  def default_generate_text(provider_module, %Model{} = model, prompt, opts \\ []) do
    system_prompt = Keyword.get(opts, :system_prompt)

    with {:ok, _} <- Util.Validation.validate_prompt(prompt),
         {:ok, response} <-
           Request.HTTP.do_http_request(
             provider_module,
             model,
             Request.Builder.build_chat_completion_body(
               provider_module,
               model,
               prompt,
               system_prompt,
               Util.Options.merge_model_options(provider_module, model, opts)
             ),
             Util.Options.merge_model_options(provider_module, model, opts)
           ) do
      case Response.Parser.extract_text_response(response) do
        {:ok, text, meta} ->
          if meta && meta.cost do
            Logger.info("💰 Generated text cost: #{CostCalculator.format_cost(meta.cost)}")
          end

          {:ok, text}

        error ->
          error
      end
    end
  end

  @doc """
  Default implementation for streaming text using OpenAI-style chat completions.
  """
  @spec default_stream_text(module(), Model.t(), String.t() | [Message.t()], keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def default_stream_text(provider_module, %Model{} = model, prompt, opts \\ []) do
    system_prompt = Keyword.get(opts, :system_prompt)

    with {:ok, _} <- Util.Validation.validate_prompt(prompt) do
      merged_opts =
        Util.Options.merge_model_options(provider_module, model, opts)
        |> Keyword.put(:stream, true)

      request_body =
        Request.Builder.build_chat_completion_body(provider_module, model, prompt, system_prompt, merged_opts)

      Request.HTTP.do_stream_request(provider_module, model, request_body, merged_opts)
    end
  end

  @doc """
  Default implementation for generating structured data using OpenAI-style chat completions.

  Supports retry logic for validation failures via `max_retries` option.
  """
  @spec default_generate_object(module(), Model.t(), String.t() | [Message.t()], map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def default_generate_object(provider_module, %Model{} = model, prompt, schema, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, model.max_retries || 3)
    do_generate_object_with_retry(provider_module, model, prompt, schema, opts, max_retries, 0)
  end

  @doc """
  Default implementation for streaming structured data using OpenAI-style chat completions.

  Returns a stream of text content chunks, similar to stream_text but for structured output.
  Final validation should be handled by the consumer.
  """
  @spec default_stream_object(module(), Model.t(), String.t() | [Message.t()], map() | keyword(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, Error.t()}
  def default_stream_object(provider_module, %Model{} = model, prompt, schema, opts \\ []) do
    system_prompt = Request.Builder.build_schema_system_prompt(schema, Keyword.get(opts, :system_prompt))

    with {:ok, _} <- Util.Validation.validate_prompt(prompt),
         {:ok, _} <- Util.Validation.validate_schema(schema) do
      merged_opts =
        Util.Options.merge_model_options(provider_module, model, opts)
        |> Keyword.put(:stream, true)
        |> Util.Options.maybe_add_json_mode(provider_module)

      request_body =
        Request.Builder.build_chat_completion_body(provider_module, model, prompt, system_prompt, merged_opts)

      # Return stream of text chunks for structured output - validation handled by consumer
      Request.HTTP.do_stream_request(provider_module, model, request_body, merged_opts)
    end
  end

  # Private retry logic for generate_object
  @spec do_generate_object_with_retry(
          module(),
          Model.t(),
          String.t() | [Message.t()],
          map() | keyword(),
          keyword(),
          non_neg_integer(),
          non_neg_integer()
        ) ::
          {:ok, map()} | {:error, Error.t()}
  defp do_generate_object_with_retry(provider_module, model, prompt, schema, opts, max_retries, attempt) do
    system_prompt = Request.Builder.build_schema_system_prompt(schema, Keyword.get(opts, :system_prompt))

    with {:ok, _} <- Util.Validation.validate_prompt(prompt),
         {:ok, _} <- Util.Validation.validate_schema(schema) do
      merged_opts =
        Util.Options.merge_model_options(provider_module, model, opts)
        |> Util.Options.maybe_add_json_mode(provider_module)

      with {:ok, response} <-
             Request.HTTP.do_http_request(
               provider_module,
               model,
               Request.Builder.build_chat_completion_body(provider_module, model, prompt, system_prompt, merged_opts),
               merged_opts
             ),
           {:ok, object, meta} <- Response.Parser.extract_object_response(response),
           {:ok, schema_struct} <- ObjectSchema.new(schema),
           {:ok, validated_object} <- ObjectSchema.validate(schema_struct, object) do
        if meta && meta.cost do
          Logger.info("💰 Generated object cost: #{CostCalculator.format_cost(meta.cost)}")
        end

        {:ok, validated_object}
      else
        {:error, %SchemaValidation{} = error} when attempt < max_retries ->
          # Build retry prompt with validation error feedback
          retry_prompt = build_retry_prompt(prompt, schema, error)
          do_generate_object_with_retry(provider_module, model, retry_prompt, schema, opts, max_retries, attempt + 1)

        {:error, _} = error ->
          error
      end
    end
  end

  @doc """
  Builds a retry prompt with validation error feedback.
  """
  @spec build_retry_prompt(String.t() | [Message.t()], map() | keyword(), SchemaValidation.t()) :: String.t()
  def build_retry_prompt(original_prompt, _schema, %SchemaValidation{validation_errors: errors}) do
    error_feedback = format_validation_errors_for_retry(errors)

    """
    #{original_prompt}

    VALIDATION ERROR: The previous response failed schema validation with the following errors:
    #{error_feedback}

    Please correct these issues and respond with valid JSON that strictly follows the required schema.
    """
  end

  @spec format_validation_errors_for_retry(list() | term()) :: String.t()
  defp format_validation_errors_for_retry(errors) when is_list(errors) do
    errors
    |> Enum.map_join("\n", &format_single_validation_error/1)
  end

  defp format_validation_errors_for_retry(_), do: "Invalid data format"

  @spec format_single_validation_error(map() | String.t() | term()) :: String.t()
  defp format_single_validation_error(%{field: field, message: message}) do
    "- #{field}: #{message}"
  end

  defp format_single_validation_error(%{path: path, message: message}) when is_list(path) do
    path_str = Enum.join(path, ".")
    "- #{path_str}: #{message}"
  end

  defp format_single_validation_error(error) when is_binary(error) do
    "- #{error}"
  end

  defp format_single_validation_error(error) do
    "- #{inspect(error)}"
  end
end
