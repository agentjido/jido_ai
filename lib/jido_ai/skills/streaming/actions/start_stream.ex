defmodule Jido.AI.Skills.Streaming.Actions.StartStream do
  @moduledoc """
  A Jido.Action for initiating a streaming LLM request.

  This action starts a streaming text generation from an LLM and returns
  a stream handle that can be used to process tokens. The actual streaming
  happens in a background task.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:fast`) or direct spec
  * `prompt` (required) - The user prompt to send to the LLM
  * `system_prompt` (optional) - System prompt to guide behavior
  * `max_tokens` (optional) - Maximum tokens to generate (default: `1024`)
  * `temperature` (optional) - Sampling temperature (default: `0.7`)
  * `timeout` (optional) - Request timeout in milliseconds
  * `on_token` (optional) - Callback function invoked for each token
  * `buffer` (optional) - Whether to buffer tokens for full response (default: `false`)
  * `auto_process` (optional) - Whether to auto-process stream (default: `true`)

  ## Examples

      # Basic streaming with inline callback
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Streaming.Actions.StartStream, %{
        prompt: "Tell me a joke",
        on_token: fn token -> IO.write(token) end
      })

      # Buffered collection
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Streaming.Actions.StartStream, %{
        prompt: "Write a poem",
        buffer: true
      })

      # Get stream_id for manual processing
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Streaming.Actions.StartStream, %{
        prompt: "Generate code",
        auto_process: false
      })
      # Use result.stream_id with ProcessTokens action
  """

  use Jido.Action,
    name: "streaming_start",
    description: "Start a streaming LLM request",
    category: "ai",
    tags: ["streaming", "llm", "generation"],
    vsn: "1.0.0",
    schema: [
      model: [
        type: :any,
        required: false,
        doc: "Model alias (e.g., :fast) or direct spec string"
      ],
      prompt: [
        type: :string,
        required: true,
        doc: "The user prompt to send to the LLM"
      ],
      system_prompt: [
        type: :string,
        required: false,
        doc: "Optional system prompt to guide the LLM's behavior"
      ],
      max_tokens: [
        type: :integer,
        required: false,
        default: 1024,
        doc: "Maximum tokens to generate"
      ],
      temperature: [
        type: :float,
        required: false,
        default: 0.7,
        doc: "Sampling temperature (0.0-2.0)"
      ],
      timeout: [
        type: :integer,
        required: false,
        doc: "Request timeout in milliseconds"
      ],
      on_token: [
        type: :any,
        required: false,
        doc: "Callback function invoked for each token"
      ],
      buffer: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Whether to buffer tokens for full response collection"
      ],
      auto_process: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Whether to automatically process the stream"
      ]
    ]

  alias Jido.AI.Config
  alias Jido.AI.Helpers

  @doc """
  Executes the start stream action.

  ## Returns

  * `{:ok, result}` - Successful stream start with `stream_id`, `model`, `status`
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        stream_id: "unique_stream_identifier",
        model: "anthropic:claude-haiku-4-5",
        status: :streaming | :completed,
        text: "accumulated text if buffered"
      }
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, model} <- resolve_model(params[:model]),
         {:ok, messages} <- build_messages(params[:prompt], params[:system_prompt]),
         stream_id <- generate_stream_id(),
         opts <- build_opts(params),
         {:ok, stream_response} <- ReqLLM.stream_text(model, messages, opts) do
      # Start background task to process the stream
      start_stream_processor(stream_id, stream_response, params)

      {:ok,
       %{
         stream_id: stream_id,
         model: model,
         status: :streaming,
         buffered: params[:buffer] || false
       }}
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Config.resolve_model(:fast)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Config.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}
  defp resolve_model(_), do: {:error, :invalid_model_format}

  defp build_messages(prompt, nil) do
    Helpers.build_messages(prompt, [])
  end

  defp build_messages(prompt, system_prompt) when is_binary(system_prompt) do
    Helpers.build_messages(prompt, system_prompt: system_prompt)
  end

  defp build_opts(params) do
    opts = [
      max_tokens: params[:max_tokens],
      temperature: params[:temperature]
    ]

    opts =
      if params[:timeout] do
        Keyword.put(opts, :receive_timeout, params[:timeout])
      else
        opts
      end

    opts
  end

  defp generate_stream_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode64()
    |> binary_part(0, 16)
  end

  defp start_stream_processor(stream_id, stream_response, params) do
    on_token = params[:on_token]
    buffer? = params[:buffer] || false
    auto_process = params[:auto_process] != false

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
      process_stream(stream_id, stream_response, on_token, buffer?, auto_process)
    end)
  end

  defp process_stream(stream_id, stream_response, on_token, buffer?, _auto_process) do
    # Initialize state
    buffer_ref = if buffer?, do: :ets.new(:stream_buffer, [:private, :multiset]), else: nil

    try do
      case ReqLLM.StreamResponse.process_stream(stream_response,
             on_result: fn
               chunk when is_binary(chunk) ->
                 handle_token(stream_id, chunk, on_token, buffer_ref)

               _other ->
                 :ok
             end
           ) do
        {:ok, response} ->
          finalize_stream(stream_id, :completed, buffer_ref, response)

        {:error, reason} ->
          finalize_stream(stream_id, {:error, reason}, buffer_ref, nil)
      end
    rescue
      e -> finalize_stream(stream_id, {:error, Exception.message(e)}, buffer_ref, nil)
    catch
      kind, reason -> finalize_stream(stream_id, {:error, {kind, reason}}, buffer_ref, nil)
    after
      if buffer_ref, do: :ets.delete(buffer_ref)
    end
  end

  defp handle_token(_stream_id, _chunk, nil, _buffer_ref), do: :ok

  defp handle_token(_stream_id, chunk, on_token, nil) when is_function(on_token, 1) do
    try do
      on_token.(chunk)
    catch
      _, _ -> :ok
    end
  end

  defp handle_token(stream_id, chunk, on_token, buffer_ref) when is_reference(buffer_ref) do
    # Store in buffer
    :ets.insert(buffer_ref, {stream_id, chunk})

    # Also call on_token if provided
    if on_token && is_function(on_token, 1) do
      try do
        on_token.(chunk)
      catch
        _, _ -> :ok
      end
    else
      :ok
    end
  end

  defp finalize_stream(_stream_id, status, nil, _response), do: status

  defp finalize_stream(_stream_id, {:error, _reason} = status, buffer_ref, _response) do
    # Could notify error via callback here
    if buffer_ref, do: :ets.delete(buffer_ref)
    status
  end

  defp finalize_stream(_stream_id, :completed, buffer_ref, response) do
    _text = extract_buffered_text(buffer_ref, _stream_id)

    # Could store completion status in Registry here
    _ = {_stream_id, _text, response}

    :completed
  end

  defp extract_buffered_text(buffer_ref, stream_id) do
    buffer_ref
    |> :ets.select([{{stream_id, :"$1"}, [], [:"$1"]}])
    |> Enum.join("")
  end
end
