defmodule Jido.AI.Context do
  @moduledoc """
  Projects committed Session or Thread Signals into model messages.

  A projection reads complete request and reply pairs. It does not change the
  Session or Thread. Incomplete requests and replies without a matching
  request are not sent to the model.
  """

  alias Jido.{Session, Signal, Thread}

  @type error_reason ::
          :invalid_context_source
          | :invalid_projection_action
          | {:invalid_projection_options, term()}
          | {:invalid_projection_signal, non_neg_integer(), term()}

  @doc "Projects complete SignalAction turns into a ReqLLM context."
  @spec project(Session.t() | Thread.t(), module(), keyword()) ::
          {:ok, ReqLLM.Context.t()} | {:error, error_reason()}
  def project(source, signal_action, opts \\ [])

  def project(source, signal_action, opts) when is_list(opts) do
    with {:ok, thread} <- thread(source),
         :ok <- signal_action(signal_action),
         {:ok, fields} <- fields(opts),
         {:ok, pairs} <- pairs(thread.signals, signal_action, fields) do
      messages =
        Enum.flat_map(pairs, fn {_index, input, output} ->
          [ReqLLM.Context.user(input), ReqLLM.Context.assistant(output)]
        end)

      {:ok, ReqLLM.Context.new(messages)}
    end
  end

  def project(_source, _signal_action, opts),
    do: {:error, {:invalid_projection_options, opts}}

  @doc "Projects complete turns or raises."
  @spec project!(Session.t() | Thread.t(), module(), keyword()) :: ReqLLM.Context.t()
  def project!(source, signal_action, opts \\ []) do
    case project(source, signal_action, opts) do
      {:ok, context} -> context
      {:error, reason} -> raise ArgumentError, "invalid AI context projection: #{inspect(reason)}"
    end
  end

  defp thread(%Session{} = session) do
    with :ok <- Session.validate(session), do: {:ok, session.thread}
  end

  defp thread(%Thread{} = thread) do
    with :ok <- Thread.validate(thread), do: {:ok, thread}
  end

  defp thread(_source), do: {:error, :invalid_context_source}

  defp signal_action(module) do
    if Jido.SignalAction.defined?(module) and module.__signal_action__().output != nil,
      do: :ok,
      else: {:error, :invalid_projection_action}
  end

  defp fields(opts) do
    if Keyword.keyword?(opts) and Enum.sort(Keyword.keys(opts)) == [:input, :output] do
      input = Keyword.fetch!(opts, :input)
      output = Keyword.fetch!(opts, :output)

      if valid_field?(input) and valid_field?(output),
        do: {:ok, %{input: input, output: output}},
        else: {:error, {:invalid_projection_options, opts}}
    else
      {:error, {:invalid_projection_options, opts}}
    end
  end

  defp valid_field?(field) when is_atom(field) and field not in [nil, true, false], do: true
  defp valid_field?(field) when is_binary(field) and byte_size(field) > 0, do: true
  defp valid_field?(_field), do: false

  defp pairs(signals, signal_action, fields) do
    input_type = signal_action.type()
    output = signal_action.__signal_action__().output

    signals
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, {%{}, []}}, fn {signal, index}, {:ok, {pending, pairs}} ->
      cond do
        signal.type == input_type ->
          case input(signal, signal_action, fields.input) do
            {:ok, value} -> {:cont, {:ok, {Map.put(pending, signal.id, {index, value}), pairs}}}
            {:error, reason} -> {:halt, {:error, {:invalid_projection_signal, index, reason}}}
          end

        signal.type == output.type ->
          case output(signal, output.schema, fields.output, pending) do
            {:ok, nil} ->
              {:cont, {:ok, {pending, pairs}}}

            {:ok, {request_id, request_index, request_value, reply_value}} ->
              pair = {request_index, request_value, reply_value}
              {:cont, {:ok, {Map.delete(pending, request_id), [pair | pairs]}}}

            {:error, reason} ->
              {:halt, {:error, {:invalid_projection_signal, index, reason}}}
          end

        true ->
          {:cont, {:ok, {pending, pairs}}}
      end
    end)
    |> case do
      {:ok, {_pending, pairs}} -> {:ok, Enum.sort_by(pairs, &elem(&1, 0))}
      error -> error
    end
  end

  defp input(%Signal{} = signal, signal_action, field) do
    with {:ok, data} <- signal_action.validate_data(signal.data) do
      text_field(data, field)
    end
  end

  defp output(%Signal{} = signal, schema, field, pending) do
    request_id = Signal.get_context(signal, "jidocausationid")

    case Map.fetch(pending, request_id) do
      {:ok, {request_index, request_value}} ->
        with {:ok, data} <- Zoi.parse(schema, signal.data),
             {:ok, reply_value} <- text_field(data, field) do
          {:ok, {request_id, request_index, request_value, reply_value}}
        end

      :error ->
        {:ok, nil}
    end
  end

  defp text_field(data, field) when is_map(data) do
    value = Map.get(data, field, Map.get(data, alternate(field)))

    if is_binary(value), do: {:ok, value}, else: {:error, {:invalid_text_field, field}}
  end

  defp alternate(field) when is_atom(field), do: Atom.to_string(field)

  defp alternate(field) when is_binary(field) do
    try do
      String.to_existing_atom(field)
    rescue
      ArgumentError -> nil
    end
  end
end
