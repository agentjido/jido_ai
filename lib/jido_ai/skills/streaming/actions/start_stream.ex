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
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :fast) or direct spec string")
          |> Zoi.optional(),
        prompt: Zoi.string(description: "The user prompt to send to the LLM"),
        system_prompt:
          Zoi.string(description: "Optional system prompt to guide the LLM's behavior")
          |> Zoi.optional(),
        max_tokens:
          Zoi.integer(description: "Maximum tokens to generate")
          |> Zoi.default(1024)
          |> Zoi.optional(),
        temperature:
          Zoi.float(description: "Sampling temperature (0.0-2.0)")
          |> Zoi.default(0.7)
          |> Zoi.optional(),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
        on_token: Zoi.any(description: "Callback function invoked for each token") |> Zoi.optional(),
        buffer:
          Zoi.boolean(description: "Whether to buffer tokens for full response collection")
          |> Zoi.default(false)
          |> Zoi.optional(),
        auto_process:
          Zoi.boolean(description: "Whether to automatically process the stream")
          |> Zoi.default(true)
          |> Zoi.optional(),
        task_supervisor:
          Zoi.any(description: "Task supervisor pid for background stream processing")
          |> Zoi.optional()
      })

  alias Jido.AI.Config
  alias Jido.AI.Helpers
  alias Jido.AI.Security

  # Dialyzer has incomplete PLT information about req_llm dependencies
  @dialyzer [
    {:nowarn_function, run: 2},
    {:nowarn_function, build_opts: 1},
    {:nowarn_function, start_stream_processor: 3},
    {:nowarn_function, process_stream: 5},
    {:nowarn_function, handle_token: 4},
    {:nowarn_function, finalize_stream: 4},
    {:nowarn_function, extract_buffered_text: 2}
  ]

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
    with {:ok, validated_params} <- validate_and_sanitize_params(params),
         {:ok, model} <- resolve_model(validated_params[:model]),
         context = build_messages(validated_params[:prompt], validated_params[:system_prompt]),
         {:ok, stream_id} <- Security.generate_stream_id() |> Security.validate_stream_id(),
         opts = build_opts(validated_params),
         {:ok, stream_response} <- ReqLLM.stream_text(model, context.messages, opts) do
      # Start background task to process the stream
      start_stream_processor(stream_id, stream_response, validated_params)

      {:ok,
       %{
         stream_id: stream_id,
         model: model,
         status: :streaming,
         buffered: validated_params[:buffer] || false
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

  # Validates and sanitizes input parameters to prevent security issues
  defp validate_and_sanitize_params(params) do
    with {:ok, _prompt} <-
           Security.validate_string(params[:prompt], max_length: Security.max_input_length()),
         {:ok, _validated} <- validate_system_prompt_if_needed(params),
         {:ok, validated_callback} <- validate_callback_if_needed(params) do
      {:ok, Map.put(params, :on_token, validated_callback)}
    else
      {:error, :empty_string} -> {:error, :prompt_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_system_prompt_if_needed(%{system_prompt: system_prompt}) when is_binary(system_prompt) do
    Security.validate_string(system_prompt, max_length: Security.max_prompt_length())
  end

  defp validate_system_prompt_if_needed(_params), do: {:ok, nil}

  defp validate_callback_if_needed(%{on_token: on_token, task_supervisor: task_supervisor})
       when is_function(on_token) do
    supervisor = resolve_task_supervisor(task_supervisor)

    Security.validate_and_wrap_callback(
      on_token,
      timeout: Security.callback_timeout(),
      task_supervisor: supervisor
    )
  end

  defp validate_callback_if_needed(%{on_token: on_token}) when is_function(on_token) do
    task_supervisor = resolve_task_supervisor(nil)

    Security.validate_and_wrap_callback(
      on_token,
      timeout: Security.callback_timeout(),
      task_supervisor: task_supervisor
    )
  end

  defp validate_callback_if_needed(_params), do: {:ok, nil}

  defp start_stream_processor(stream_id, stream_response, params) do
    on_token = params[:on_token]
    buffer? = params[:buffer] || false
    auto_process = params[:auto_process] != false
    task_supervisor = resolve_task_supervisor(params[:task_supervisor])

    Task.Supervisor.start_child(task_supervisor, fn ->
      process_stream(stream_id, stream_response, on_token, buffer?, auto_process)
    end)
  end

  defp resolve_task_supervisor(supervisor) when is_pid(supervisor), do: supervisor

  defp resolve_task_supervisor(nil) do
    case Application.get_env(:jido_ai, :task_supervisor) do
      nil ->
        raise """
        Task supervisor not configured.

        For streaming actions, you must either:
        1. Pass task_supervisor as a parameter
        2. Configure it in application environment:
           Application.put_env(:jido_ai, :task_supervisor, supervisor_pid)

        When using Jido.AI with agents, the supervisor is automatically
        configured. For standalone action execution, you must provide it.
        """

      supervisor when is_pid(supervisor) ->
        supervisor
    end
  end

  defp process_stream(stream_id, stream_response, on_token, buffer?, _auto_process) do
    # Initialize state
    buffer_ref = if buffer?, do: :ets.new(:stream_buffer, [:private, :multiset])

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

  defp handle_token(stream_id, chunk, on_token, buffer_ref) do
    cond do
      # Buffer exists (ETS tid is always truthy)
      buffer_ref != nil ->
        # Store in buffer
        :ets.insert(buffer_ref, {stream_id, chunk})

        # Also call on_token if provided (already validated and wrapped)
        if on_token && is_function(on_token, 1) do
          try do
            on_token.(chunk)
          catch
            _, _ -> :ok
          end
        else
          :ok
        end

      # No buffer, has callback
      on_token != nil and is_function(on_token, 1) ->
        try do
          on_token.(chunk)
        catch
          _, _ -> :ok
        end

      # No buffer, no callback
      true ->
        :ok
    end
  end

  defp finalize_stream(_stream_id, status, nil, _response), do: status

  defp finalize_stream(_stream_id, {:error, _reason} = status, buffer_ref, _response) do
    # Could notify error via callback here
    if buffer_ref, do: :ets.delete(buffer_ref)
    status
  end

  defp finalize_stream(stream_id, :completed, buffer_ref, _response) do
    # Extract buffered text for potential future use
    _ = extract_buffered_text(buffer_ref, stream_id)

    # Could store completion status in Registry here

    :completed
  end

  defp extract_buffered_text(buffer_ref, stream_id) do
    buffer_ref
    |> :ets.select([{{stream_id, :"$1"}, [], [:"$1"]}])
    |> Enum.join("")
  end
end
