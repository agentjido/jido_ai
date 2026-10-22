defmodule Jido.AI.Test.LiveTrace do
  @moduledoc """
  Writes a small, normalized trace for one live AI request.

  Traces contain the test input and selected response fields. They do not
  contain HTTP headers, provider metadata, API keys, or raw provider payloads.
  Use synthetic test prompts because the input and output text are stored.
  """

  @trace_root Path.expand("../../tmp/jido_ai_traces", __DIR__)
  @option_keys [:max_tokens, :temperature, :receive_timeout]
  @usage_keys [:input_tokens, :output_tokens, :total_tokens]

  @type request :: %{
          required(:scenario) => String.t(),
          required(:model) => String.t(),
          required(:instructions) => String.t(),
          required(:input) => String.t(),
          required(:options) => keyword()
        }

  @spec capture(request(), (-> term())) :: {term(), Path.t()}
  def capture(request, fun) when is_map(request) and is_function(fun, 0) do
    started_at = DateTime.utc_now()
    started_ms = System.monotonic_time(:millisecond)

    try do
      result = fun.()
      duration_ms = System.monotonic_time(:millisecond) - started_ms
      trace = build_trace(request, result, started_at, duration_ms)
      {result, write_trace!(request, trace, started_at)}
    rescue
      error ->
        duration_ms = System.monotonic_time(:millisecond) - started_ms
        trace = build_exception_trace(request, error, started_at, duration_ms)
        write_trace!(request, trace, started_at)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        duration_ms = System.monotonic_time(:millisecond) - started_ms
        trace = build_catch_trace(request, kind, started_at, duration_ms)
        write_trace!(request, trace, started_at)
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  defp build_trace(request, {:ok, %ReqLLM.Response{} = response}, started_at, duration_ms) do
    output = normalize_response(response)

    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "ok")
    |> Map.put("events", [started_event(request), completed_event(output, duration_ms)])
  end

  defp build_trace(request, {:ok, text}, started_at, duration_ms) when is_binary(text) do
    output = %{
      "model" => request.model,
      "text" => text,
      "finish_reason" => nil,
      "tool_call_count" => 0,
      "usage" => %{}
    }

    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "ok")
    |> Map.put("events", [started_event(request), completed_event(output, duration_ms)])
  end

  defp build_trace(request, {:ok, object}, started_at, duration_ms) when is_map(object) do
    output = %{
      "model" => request.model,
      "object" => object,
      "finish_reason" => nil,
      "tool_call_count" => 0,
      "usage" => %{}
    }

    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "ok")
    |> Map.put("events", [started_event(request), completed_event(output, duration_ms)])
  end

  defp build_trace(request, {:error, reason}, started_at, duration_ms) do
    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "error")
    |> Map.put("events", [started_event(request), failed_event(error_type(reason), duration_ms)])
  end

  defp build_trace(request, result, started_at, duration_ms) do
    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "unexpected_result")
    |> Map.put("events", [started_event(request), failed_event(error_type(result), duration_ms)])
  end

  defp build_exception_trace(request, error, started_at, duration_ms) do
    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "exception")
    |> Map.put("events", [started_event(request), failed_event(error_type(error), duration_ms)])
  end

  defp build_catch_trace(request, kind, started_at, duration_ms) do
    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "caught")
    |> Map.put("events", [started_event(request), failed_event(to_string(kind), duration_ms)])
  end

  defp base_trace(request, started_at, duration_ms) do
    %{
      "schema_version" => 1,
      "scenario" => request.scenario,
      "recorded_at" => DateTime.to_iso8601(started_at),
      "duration_ms" => duration_ms
    }
  end

  defp started_event(request) do
    %{
      "sequence" => 1,
      "offset_ms" => 0,
      "type" => "ai.request.started",
      "data" => %{
        "model" => request.model,
        "instructions" => request.instructions,
        "input" => request.input,
        "options" => normalize_options(request.options)
      }
    }
  end

  defp completed_event(output, duration_ms) do
    %{
      "sequence" => 2,
      "offset_ms" => duration_ms,
      "type" => "ai.response.completed",
      "data" => output
    }
  end

  defp failed_event(type, duration_ms) do
    %{
      "sequence" => 2,
      "offset_ms" => duration_ms,
      "type" => "ai.response.failed",
      "data" => %{"error_type" => type}
    }
  end

  defp normalize_response(response) do
    %{
      "model" => response.model,
      "text" => ReqLLM.Response.text(response),
      "finish_reason" => normalize_atom(response.finish_reason),
      "tool_call_count" => response |> ReqLLM.Response.tool_calls() |> length(),
      "usage" => normalize_usage(response.usage)
    }
  end

  defp normalize_options(options) do
    options
    |> Keyword.take(@option_keys)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_usage(usage) when is_map(usage) do
    Map.new(@usage_keys, fn key ->
      {to_string(key), Map.get(usage, key) || Map.get(usage, to_string(key))}
    end)
  end

  defp normalize_usage(_usage), do: %{}

  defp normalize_atom(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_atom(value), do: value

  defp error_type(%module{}), do: inspect(module)
  defp error_type({type, _reason}) when is_atom(type), do: Atom.to_string(type)
  defp error_type(type) when is_atom(type), do: Atom.to_string(type)
  defp error_type(_reason), do: "unknown"

  defp write_trace!(request, trace, started_at) do
    path = trace_path(request, started_at)
    temporary_path = path <> ".tmp"

    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(temporary_path, Jason.encode!(trace, pretty: true))
    File.rename!(temporary_path, path)
    path
  end

  defp trace_path(request, started_at) do
    {provider, model} = split_model(request.model)

    filename =
      started_at
      |> DateTime.to_iso8601()
      |> slug()
      |> Kernel.<>("_#{System.unique_integer([:positive])}.json")

    Path.join([@trace_root, slug(request.scenario), slug(provider), slug(model), filename])
  end

  defp split_model(model) do
    case String.split(model, ":", parts: 2) do
      [provider, name] -> {provider, name}
      [name] -> {"unknown", name}
    end
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end
end
