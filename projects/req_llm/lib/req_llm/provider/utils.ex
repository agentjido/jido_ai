defmodule ReqLLM.Provider.Utils do
  @moduledoc """
  Shared utilities for provider implementations.

  Contains common functions used across multiple providers to eliminate
  duplication and ensure consistency.

  ## Examples

      iex> ReqLLM.Provider.Utils.normalize_messages("Hello world")
      [%{role: "user", content: "Hello world"}]

      iex> messages = [%{role: "user", content: "Hi"}]
      iex> ReqLLM.Provider.Utils.normalize_messages(messages)
      [%{role: "user", content: "Hi"}]

      iex> spec = %{default_model: "gpt-4", models: %{"gpt-3.5" => %{}, "gpt-4" => %{}}}
      iex> ReqLLM.Provider.Utils.default_model(spec)
      "gpt-4"

      iex> spec = %{default_model: nil, models: %{"claude-3-haiku" => %{}, "claude-3-opus" => %{}}}
      iex> ReqLLM.Provider.Utils.default_model(spec)
      "claude-3-haiku"
  """

  @doc """
  Normalizes various prompt formats into a standardized messages list.

  ## Parameters

  - `prompt` - Can be a string, list of messages, or any other type that can be converted to string

  ## Returns

  A list of message maps with `:role` and `:content` keys.

  ## Examples

      iex> ReqLLM.Provider.Utils.normalize_messages("What is the weather?")
      [%{role: "user", content: "What is the weather?"}]

      iex> messages = [%{role: "user", content: "Hello"}, %{role: "assistant", content: "Hi there!"}]
      iex> ReqLLM.Provider.Utils.normalize_messages(messages)
      [%{role: "user", content: "Hello"}, %{role: "assistant", content: "Hi there!"}]

      iex> ReqLLM.Provider.Utils.normalize_messages(123)
      [%{role: "user", content: "123"}]
  """
  @spec normalize_messages(binary() | list() | term()) :: [map()]
  def normalize_messages(prompt) when is_binary(prompt) do
    [%{role: "user", content: prompt}]
  end

  def normalize_messages(messages) when is_list(messages) do
    messages
  end

  def normalize_messages(prompt) do
    [%{role: "user", content: to_string(prompt)}]
  end

  @doc """
  Gets the default model for a provider spec.

  Falls back to the first available model if no default is specified.

  ## Parameters

  - `spec` - Provider spec struct with `:default_model` and `:models` fields

  ## Returns

  The default model string, or `nil` if no models are available.

  ## Examples

      iex> spec = %{default_model: "gpt-4", models: %{"gpt-3.5" => %{}, "gpt-4" => %{}}}
      iex> ReqLLM.Provider.Utils.default_model(spec)
      "gpt-4"

      iex> spec = %{default_model: nil, models: %{"model-a" => %{}, "model-b" => %{}}}
      iex> ReqLLM.Provider.Utils.default_model(spec)
      "model-a"

      iex> spec = %{default_model: nil, models: %{}}
      iex> ReqLLM.Provider.Utils.default_model(spec)
      nil
  """
  @spec default_model(map()) :: binary() | nil
  def default_model(spec) do
    spec.default_model ||
      case Map.keys(spec.models) do
        [first_model | _] -> first_model
        [] -> nil
      end
  end

  @doc """
  Creates standard HTTP headers for JSON API requests.

  ## Parameters

  - `extra_headers` - Optional list of additional header tuples to include

  ## Returns

  A list of header tuples with content-type set to application/json.

  ## Examples

      iex> ReqLLM.Provider.Utils.json_headers()
      [{"content-type", "application/json"}]

      iex> ReqLLM.Provider.Utils.json_headers([{"authorization", "Bearer token"}])
      [{"content-type", "application/json"}, {"authorization", "Bearer token"}]
  """
  @spec json_headers(list()) :: list()
  def json_headers(extra_headers \\ []) do
    [{"content-type", "application/json"}] ++ extra_headers
  end

  @doc """
  Parses error responses into ReqLLM.Error.API.Response exceptions.

  Handles both structured error responses with message fields and fallback
  to HTTP status codes.

  ## Parameters

  - `status` - HTTP status code
  - `body` - Response body (map or other)

  ## Returns

  A `ReqLLM.Error.API.Response` exception struct.

  ## Examples

      iex> body = %{"error" => %{"message" => "Invalid API key"}}
      iex> error = ReqLLM.Provider.Utils.parse_error_response(401, body)
      iex> error.reason
      "Invalid API key"

      iex> error = ReqLLM.Provider.Utils.parse_error_response(500, %{})
      iex> error.reason
      "HTTP 500"
  """
  @spec parse_error_response(integer(), any()) :: ReqLLM.Error.API.Response.t()
  def parse_error_response(status, body) do
    error_message =
      case body do
        %{"error" => %{"message" => message}} -> message
        _ -> "HTTP #{status}"
      end

    ReqLLM.Error.API.Response.exception(reason: error_message, status: status)
  end

  @doc """
  Parses Server-Sent Event chunks for streaming responses.

  Common logic for parsing SSE format used by both OpenAI and Anthropic.

  ## Parameters

  - `body` - Raw SSE response body
  - `filter_event` - Event type to filter for (e.g., "data", "message")
  - `extract_fn` - Function to extract content from parsed data

  ## Returns

  `{:ok, combined_content}` or `{:error, reason}`.

  ## Examples

      iex> body = "event: data\\ndata: {\\"choices\\": [{\\"delta\\": {\\"content\\": \\"Hello\\"}}]}\\n\\n"
      iex> extract_fn = fn data -> get_in(data, ["choices", Access.at(0), "delta", "content"]) end
      iex> ReqLLM.Provider.Utils.parse_sse_stream(body, "data", extract_fn)
      {:ok, "Hello"}
  """
  @spec parse_sse_stream(binary(), binary() | nil, function()) ::
          {:ok, binary()} | {:error, ReqLLM.Error.API.Response.t()}
  def parse_sse_stream(body, filter_event, extract_fn) do
    case ServerSentEvents.parse(body) do
      {:ok, {events, _rest}} ->
        if Enum.empty?(events) do
          {:error,
           ReqLLM.Error.API.Response.exception(reason: "No events found in streaming response")}
        else
          content_parts =
            events
            |> Enum.filter(&(&1.type == nil or &1.type == filter_event))
            |> Enum.flat_map(& &1.lines)
            |> Enum.reject(&(&1 in [nil, "", "[DONE]"]))
            |> Enum.map(&Jason.decode/1)
            |> Enum.filter(&match?({:ok, _}, &1))
            |> Enum.map(fn {:ok, data} -> data end)
            |> Enum.map(extract_fn)
            |> Enum.filter(&is_binary/1)

          case content_parts do
            [] ->
              {:error,
               ReqLLM.Error.API.Response.exception(
                 reason: "No content found in streaming response"
               )}

            parts ->
              {:ok, Enum.join(parts, "")}
          end
        end

      {:error, reason} ->
        {:error,
         ReqLLM.Error.API.Response.exception(reason: "SSE parse error: #{inspect(reason)}")}
    end
  end

  @doc """
  Safely parses JSON chunks from streaming data.

  Handles malformed JSON and filters out empty or control chunks.

  ## Parameters

  - `raw_chunk` - Raw streaming chunk data

  ## Returns

  `{:ok, [parsed_data]}` or `{:error, reason}`.

  ## Examples

      iex> chunk = "data: {\\"test\\": \\"value\\"}\\n\\n"
      iex> ReqLLM.Provider.Utils.parse_json_chunks(chunk)
      {:ok, [%{"test" => "value"}]}
  """
  @spec parse_json_chunks(iodata()) :: {:ok, [map()]} | {:error, ReqLLM.Error.API.Response.t()}
  def parse_json_chunks(raw_chunk) do
    lines =
      raw_chunk
      |> IO.iodata_to_binary()
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    parsed_chunks =
      lines
      |> Enum.filter(&String.starts_with?(&1, "data:"))
      |> Enum.map(&String.slice(&1, 5..-1//1))
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 in ["", "[DONE]"]))
      |> Enum.map(&Jason.decode/1)

    case Enum.find(parsed_chunks, &match?({:error, _}, &1)) do
      {:error, reason} ->
        {:error,
         ReqLLM.Error.API.Response.exception(reason: "JSON decode error: #{inspect(reason)}")}

      nil ->
        valid_chunks = Enum.map(parsed_chunks, fn {:ok, data} -> data end)
        {:ok, valid_chunks}
    end
  end

  @doc """
  Conditionally attaches streaming step to a request.

  Adds the stream step for SSE parsing when streaming is enabled.

  ## Parameters

  - `request` - The Req request to potentially modify
  - `stream_enabled` - Whether streaming is enabled

  ## Returns

  The request, with streaming step attached if needed.

  ## Examples

      iex> request = %Req.Request{}
      iex> ReqLLM.Provider.Utils.maybe_append_stream_step(request, true)
      # Returns request with stream step attached

      iex> ReqLLM.Provider.Utils.maybe_append_stream_step(request, false)
      # Returns original request unchanged
  """
  @spec maybe_append_stream_step(Req.Request.t(), boolean()) :: Req.Request.t()
  def maybe_append_stream_step(req, true), do: ReqLLM.Plugins.Stream.attach(req)
  def maybe_append_stream_step(req, _), do: req

  @doc """
  Conditionally puts a value into a keyword list or map if the value is not nil.

  ## Parameters

  - `opts` - Keyword list or map to potentially modify
  - `key` - Key to add
  - `value` - Value to add (if not nil)

  ## Returns

  The keyword list or map, with key-value pair added if value is not nil.

  ## Examples

      iex> ReqLLM.Provider.Utils.maybe_put([], :name, "John")
      [name: "John"]

      iex> ReqLLM.Provider.Utils.maybe_put(%{}, :name, "John")
      %{name: "John"}

      iex> ReqLLM.Provider.Utils.maybe_put([], :name, nil)
      []

      iex> ReqLLM.Provider.Utils.maybe_put(%{}, :name, nil)
      %{}
  """
  @spec maybe_put(keyword() | map(), atom(), term()) :: keyword() | map()
  def maybe_put(opts, _key, nil), do: opts
  def maybe_put(opts, key, value) when is_list(opts), do: Keyword.put(opts, key, value)
  def maybe_put(opts, key, value) when is_map(opts), do: Map.put(opts, key, value)

  @doc """
  Raises an error if unknown options are present.

  ## Parameters

  - `opts` - Options to validate
  - `allowed` - List of allowed option keys

  ## Returns

  The original options if all keys are allowed.

  ## Raises

  `ReqLLM.Error.Invalid.Parameter` if unknown options are found.

  ## Examples

      iex> ReqLLM.Provider.Utils.reject_unknown!([temperature: 0.7], [:temperature, :max_tokens])
      [temperature: 0.7]

      iex> ReqLLM.Provider.Utils.reject_unknown!([bad_key: "value"], [:temperature])
      ** (ReqLLM.Error.Invalid.Parameter) unsupported options: [:bad_key]
  """
  @spec reject_unknown!(keyword(), [atom()]) :: keyword()
  def reject_unknown!(opts, allowed) do
    case Keyword.keys(opts) -- allowed do
      [] ->
        opts

      unknown ->
        raise ReqLLM.Error.Invalid.Parameter.exception(
                parameter: "unsupported options: #{inspect(unknown)}"
              )
    end
  end

  @doc """
  Validates generation options against a subset schema, raising on error.

  ## Parameters

  - `opts` - Options to validate
  - `allowed_keys` - Keys to include in validation schema

  ## Returns

  The validated options.

  ## Raises

  `NimbleOptions.ValidationError` if validation fails.

  ## Examples

      iex> ReqLLM.Provider.Utils.validate_subset!([temperature: 0.7], [:temperature, :max_tokens])
      [temperature: 0.7]
  """
  @spec validate_subset!(keyword(), [atom()]) :: keyword()
  def validate_subset!(opts, allowed_keys) do
    schema = ReqLLM.Provider.Options.generation_subset_schema(allowed_keys)
    NimbleOptions.validate!(opts, schema)
  end

  @doc """
  Extracts only generation options from a mixed options list.

  Unlike `ReqLLM.Provider.Options.extract_provider_options/1`, this returns
  only the generation options without the unused remainder.

  ## Parameters

  - `opts` - Mixed options list

  ## Returns

  Keyword list containing only generation options.

  ## Examples

      iex> mixed_opts = [temperature: 0.7, custom_param: "value", max_tokens: 100]
      iex> ReqLLM.Provider.Utils.extract_generation_opts(mixed_opts)
      [temperature: 0.7, max_tokens: 100]
  """
  @spec extract_generation_opts(keyword()) :: keyword()
  def extract_generation_opts(opts) do
    {generation_opts, _rest} = ReqLLM.Provider.Options.extract_provider_options(opts)
    generation_opts
  end

  @doc """
  Adds context to options if present in user options, with type validation.

  ## Parameters

  - `opts` - Current options keyword list
  - `user_opts` - Original user options to check for context

  ## Returns

  Options with context added if present.

  ## Raises

  `ReqLLM.Error.Invalid.Parameter` if context is not a ReqLLM.Context struct.

  ## Examples

      iex> context = %ReqLLM.Context{messages: []}
      iex> ReqLLM.Provider.Utils.maybe_put_context([model: "gpt-4"], [context: context])
      [model: "gpt-4", context: context]
  """
  @spec maybe_put_context(keyword(), keyword()) :: keyword()
  def maybe_put_context(opts, user_opts) do
    case Keyword.get(user_opts, :context) do
      %ReqLLM.Context{} = ctx ->
        Keyword.put(opts, :context, ctx)

      nil ->
        opts

      other ->
        raise ReqLLM.Error.Invalid.Parameter.exception(
                parameter: "context must be ReqLLM.Context, got: #{inspect(other)}"
              )
    end
  end

  @doc """
  Prepares provider options using a clean pipeline approach.

  This is the main helper that providers can use to process user options
  into a clean, validated keyword list ready for the Req request.

  ## Parameters

  - `provider_mod` - The provider module (must implement supported_provider_options/0 and default_provider_opts/0)
  - `model` - ReqLLM.Model struct
  - `user_opts` - Raw user options

  ## Returns

  Validated and processed options keyword list.

  ## Examples

      iex> model = %ReqLLM.Model{provider: :anthropic, model: "claude-3-haiku"}
      iex> user_opts = [temperature: 0.7, max_tokens: 1000]
      iex> ReqLLM.Provider.Utils.prepare_options!(MyProvider, model, user_opts)
      [temperature: 0.7, max_tokens: 1000, model: "claude-3-haiku"]
  """
  @spec prepare_options!(module(), ReqLLM.Model.t(), keyword()) :: keyword()
  def prepare_options!(provider_mod, %ReqLLM.Model{} = model, user_opts) do
    user_opts
    |> extract_generation_opts()
    |> reject_unknown!(provider_mod.supported_provider_options())
    |> validate_subset!(provider_mod.supported_provider_options())
    |> then(&Keyword.merge(provider_mod.default_provider_opts(), &1))
    |> Keyword.put(:model, model.model)
    |> maybe_put_context(user_opts)
  end
end
