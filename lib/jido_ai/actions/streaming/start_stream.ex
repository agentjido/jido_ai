defmodule Jido.AI.Actions.Streaming.StartStream do
  @moduledoc """
  A Jido.Action for initiating a streaming LLM request.

  This action starts a streaming text generation from an LLM and returns
  a stream handle that can be used to process tokens. Streams are tracked in
  `Jido.AI.Streaming.Registry` and can be consumed automatically or manually.
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

  alias Jido.AI.Security
  alias Jido.AI.Actions.Streaming.ProcessTokens
  alias Jido.AI.Streaming.Registry
  alias ReqLLM.Context

  @impl Jido.Action
  def run(params, context) do
    with {:ok, validated_params} <- validate_and_sanitize_params(params),
         {:ok, model} <- resolve_model(validated_params[:model]),
         {:ok, req_context} <- build_messages(validated_params[:prompt], validated_params[:system_prompt]),
         {:ok, stream_id} <- Security.generate_stream_id() |> Security.validate_stream_id(),
         opts = build_opts(validated_params),
         {:ok, stream_response} <- ReqLLM.stream_text(model, req_context.messages, opts),
         {:ok, _entry} <- register_stream(stream_id, model, stream_response, validated_params),
         :ok <- maybe_start_processor(stream_id, validated_params, context) do
      {:ok,
       %{
         stream_id: stream_id,
         model: model,
         status: initial_status(validated_params),
         buffered: validated_params[:buffer] || false,
         auto_process: validated_params[:auto_process] != false
       }}
    end
  end

  defp resolve_model(nil), do: {:ok, Jido.AI.resolve_model(:fast)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Jido.AI.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}
  defp resolve_model(_), do: {:error, :invalid_model_format}

  defp build_messages(prompt, nil), do: Context.normalize(prompt, [])

  defp build_messages(prompt, system_prompt) when is_binary(system_prompt) do
    Context.normalize(prompt, system_prompt: system_prompt)
  end

  defp build_opts(params) do
    opts = [
      max_tokens: params[:max_tokens],
      temperature: params[:temperature]
    ]

    if params[:timeout], do: Keyword.put(opts, :receive_timeout, params[:timeout]), else: opts
  end

  defp register_stream(stream_id, model, stream_response, params) do
    Registry.register(stream_id, %{
      status: initial_status(params),
      model: model,
      auto_process: params[:auto_process] != false,
      buffered: params[:buffer] || false,
      on_token: params[:on_token],
      stream_response: stream_response
    })
  end

  defp initial_status(params) do
    if params[:auto_process] == false, do: :pending, else: :streaming
  end

  defp maybe_start_processor(stream_id, params, context) do
    if params[:auto_process] == false do
      :ok
    else
      with {:ok, task_supervisor} <- resolve_task_supervisor(params[:task_supervisor], context),
           {:ok, _pid} <-
             Task.Supervisor.start_child(task_supervisor, fn ->
               _ = ProcessTokens.run(%{stream_id: stream_id}, context)
             end) do
        :ok
      else
        {:error, reason} = error ->
          _ = Registry.mark_error(stream_id, reason)
          error
      end
    end
  end

  defp resolve_task_supervisor(supervisor, _context) when is_pid(supervisor), do: {:ok, supervisor}

  defp resolve_task_supervisor(supervisor, _context) when is_atom(supervisor) and not is_nil(supervisor),
    do: {:ok, supervisor}

  defp resolve_task_supervisor(nil, context) do
    case context_task_supervisor(context) do
      supervisor when is_pid(supervisor) or (is_atom(supervisor) and not is_nil(supervisor)) -> {:ok, supervisor}
      _ -> {:error, :missing_task_supervisor}
    end
  end

  defp resolve_task_supervisor(_supervisor, _context), do: {:error, :invalid_task_supervisor}

  defp context_task_supervisor(%Jido.AgentServer.State{agent: %{state: state}}),
    do: context_task_supervisor(state)

  defp context_task_supervisor(%Jido.Agent{state: state}), do: context_task_supervisor(state)

  defp context_task_supervisor(context) when is_map(context) do
    context[:task_supervisor] ||
      get_in(context, [:__task_supervisor_skill__, :supervisor]) ||
      get_in(context, [:state, :__task_supervisor_skill__, :supervisor]) ||
      get_in(context, [:agent, :state, :__task_supervisor_skill__, :supervisor]) ||
      get_in(context, [:agent_state, :__task_supervisor_skill__, :supervisor])
  end

  defp context_task_supervisor(_), do: nil

  defp validate_and_sanitize_params(params) do
    with {:ok, _prompt} <-
           Security.validate_string(params[:prompt], max_length: Security.max_input_length()),
         {:ok, _validated} <- validate_system_prompt_if_needed(params),
         {:ok, on_token} <- validate_callback_if_needed(params[:on_token]) do
      {:ok, Map.put(params, :on_token, on_token)}
    else
      {:error, :empty_string} -> {:error, :prompt_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_system_prompt_if_needed(%{system_prompt: system_prompt}) when is_binary(system_prompt) do
    Security.validate_string(system_prompt, max_length: Security.max_prompt_length())
  end

  defp validate_system_prompt_if_needed(_params), do: {:ok, nil}

  defp validate_callback_if_needed(nil), do: {:ok, nil}
  defp validate_callback_if_needed(callback) when is_function(callback, 1), do: {:ok, callback}
  defp validate_callback_if_needed(_), do: {:error, :invalid_on_token_callback}
end
