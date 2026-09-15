defmodule Jido.AI.Actions.Reasoning.RunStrategy do
  @moduledoc """
  Runs a prompt in one linked private Agent and Orchestration.

  Bind a resolved `Jido.AI.Profile` in host context at
  `:jido_ai_callable_profile`. Input accepts only a nonempty string `prompt`.
  The Profile must select session mode and a supported callable method.
  Completion, failure, and cancellation stop the private runtime.
  """

  use Jido.Action,
    name: "reasoning_run_strategy",
    description: "Run a prompt with host-bound reasoning policy",
    schema: Zoi.object(%{prompt: Zoi.string() |> Zoi.min(1)}, coerce: true, unrecognized_keys: :error)

  alias Jido.AI.{Authoring, Profile, Request, Orchestration}
  alias Jido.AgentServer, as: Server

  @methods %{
    chain_of_draft: :cod,
    chain_of_thought: :cot,
    tree_of_thoughts: :tot,
    graph_of_thoughts: :got,
    trm: :trm,
    algorithm_of_thoughts: :aot,
    adaptive: :adaptive
  }

  @impl Jido.Action
  def on_before_validate_params(params) when is_map(params) and not is_struct(params) do
    case Map.to_list(params) do
      [{key, prompt}] when key in [:prompt, "prompt"] and is_binary(prompt) and byte_size(prompt) > 0 ->
        {:ok, %{prompt: prompt}}

      _ ->
        {:error, :invalid_strategy_request}
    end
  end

  def on_before_validate_params(_), do: {:error, :invalid_strategy_request}

  @doc false
  def validate_profile(%Profile{} = value) do
    with {:ok, profile} <- Profile.validate(value),
         :ok <- callable_mode(profile),
         :ok <- callable_method(profile) do
      {:ok, profile}
    end
  end

  def validate_profile(_), do: Profile.error("profile", "Expected a resolved Profile binding")

  defp callable_mode(%{requests: %{mode: :session}}), do: :ok
  defp callable_mode(_), do: Profile.error("requests.mode", "Callable reasoning requires session mode")
  defp callable_method(%{reasoning: %{method: method}}) when is_map_key(@methods, method), do: :ok
  defp callable_method(_), do: Profile.error("reasoning.method", "Unsupported callable method")

  @impl Jido.Action
  def run(params, context) do
    context = if is_map(context), do: context, else: %{}

    with {:ok, %{prompt: prompt}} <- on_before_validate_params(params),
         {:ok, value} <- bound_profile(context),
         {:ok, profile} <- validate_profile(value),
         deadline = System.monotonic_time(:millisecond) + profile.controls.timeout,
         {:ok, definition} <- runner_definition(profile),
         :ok <- time_left(deadline),
         {:ok, server} <- Server.start_link([agent: definition] ++ Map.to_list(Map.take(context, [:jido]))) do
      try do
        run_request(server, profile, prompt, context, deadline)
      after
        stop_runner(server)
      end
    end
  end

  defp bound_profile(context) do
    case Map.fetch(context, :jido_ai_callable_profile) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, :reasoning_profile_not_bound}
    end
  end

  defp run_request(server, profile, prompt, context, deadline) do
    with :ok <- time_left(deadline),
         :ok <- Server.await_ready(server, remaining(deadline)),
         :ok <- time_left(deadline),
         {:ok, handle} <-
           Request.create_and_send(server, prompt,
             signal_type: "reasoning.run",
             source: "/ai/reasoning/action",
             admission_deadline: deadline,
             admission_timeout: remaining(deadline),
             context: Map.merge(Orchestration.caller_context(context), Map.take(context, [:jido_ai_quota]))
           ) do
      result = Request.await(handle, timeout: remaining(deadline))
      if result == {:error, :timeout}, do: Orchestration.cancel(handle, reason: :timeout, timeout: 1_000)
      snapshot = fetch_snapshot(server, handle.id)
      normalize_runner_result(result, @methods[profile.reasoning.method], profile.controls.timeout, snapshot)
    end
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
  end

  defp time_left(deadline), do: if(remaining(deadline) > 0, do: :ok, else: {:error, :timeout})

  defp remaining(deadline), do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp stop_runner(server) do
    if Process.alive?(server), do: Server.stop(server, :normal, 1_000)
  catch
    :exit, _reason -> force_stop_runner(server)
  end

  defp force_stop_runner(server) do
    # A graceful stop can time out while the server is suspended or busy.
    # Unlink before killing it so that cleanup does not kill the Action owner.
    ref = Process.monitor(server)
    Process.unlink(server)
    Process.exit(server, :kill)

    receive do
      {:DOWN, ^ref, :process, ^server, _} -> :ok
    after
      1_000 -> exit(:reasoning_runner_cleanup_timeout)
    end
  end

  defp runner_definition(profile) do
    fields = %{profile.result.into => Zoi.any() |> Zoi.default(nil)}

    fields =
      case profile.memory.history do
        nil -> fields
        field -> Map.put(fields, field, Jido.AI.Thread.Projection.schema())
      end

    base = %{
      name: "jido_ai_internal_reasoning_runner",
      plugins: [],
      schema: Zoi.object(fields),
      routes: [{"reasoning.run", Authoring.ai(profile.id)}]
    }

    Authoring.lower(base, [profile])
  end

  defp fetch_snapshot(server, id) do
    with {:ok, records} <- Server.plugin_state(server, Jido.AI.Orchestration.Plugin, 1_000),
         record when is_map(record) <- records[id] do
      status =
        case record.status do
          :completed -> :success
          :failed -> :failure
          :pending -> :running
        end

      failure =
        case record.error do
          {:failed, _, details} when is_map(details) -> details
          _ -> %{}
        end

      details =
        record.meta
        |> Map.merge(Map.get(record.meta, :reasoning, %{}))
        |> Map.merge(failure)

      result =
        cond do
          record.result != nil -> record.result
          is_map_key(failure, :tree) or is_map_key(failure, :found_solution?) -> failure
          true -> failure[:result]
        end

      %{status: status, done?: record.status != :pending, result: result, details: details}
    else
      _ -> nil
    end
  catch
    :exit, _reason -> nil
  end

  defp normalize_runner_result({:ok, output}, strategy, timeout, snapshot) do
    {:ok,
     %{
       strategy: strategy,
       status: snapshot_status(snapshot, :success),
       output: output,
       usage: extract_usage(snapshot),
       diagnostics: diagnostics(timeout, snapshot, nil)
     }}
  end

  defp normalize_runner_result({:error, reason}, strategy, timeout, snapshot) do
    case maybe_recover_success(snapshot) do
      {:ok, output} ->
        {:ok,
         %{
           strategy: strategy,
           status: snapshot_status(snapshot, :success),
           output: output,
           usage: extract_usage(snapshot),
           diagnostics:
             diagnostics(timeout, snapshot, nil)
             |> Map.put(:recovered_error, Jido.AI.Error.Sanitize.sanitize_error_message(reason))
         }}

      :error ->
        {:error,
         %{
           strategy: strategy,
           status: snapshot_status(snapshot, :failure),
           output: snapshot_output(snapshot),
           usage: extract_usage(snapshot),
           diagnostics:
             diagnostics(
               timeout,
               snapshot,
               Jido.AI.Error.Sanitize.sanitize_error_message(reason)
             )
         }}
    end
  end

  defp snapshot_status(%{status: status}, _fallback) when not is_nil(status), do: status
  defp snapshot_status(_snapshot, fallback), do: fallback

  defp extract_usage(%{details: details}) when is_map(details) do
    Map.get(details, :usage, Map.get(details, "usage", %{}))
  end

  defp extract_usage(_), do: %{}

  defp diagnostics(timeout, snapshot, error) do
    %{
      timeout: timeout,
      snapshot_status: snapshot_status(snapshot, :unknown),
      snapshot_done: snapshot_done?(snapshot),
      snapshot_details: snapshot_details(snapshot),
      error: error
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == %{} end)
    |> Map.new()
  end

  defp snapshot_done?(%{done?: done?}), do: done?
  defp snapshot_done?(_), do: nil

  defp snapshot_details(%{details: details}) when is_map(details), do: details
  defp snapshot_details(_), do: %{}

  defp maybe_recover_success(snapshot) do
    output = snapshot_output(snapshot)

    if snapshot_done?(snapshot) == true and snapshot_status(snapshot, :unknown) == :success and
         not is_nil(output) do
      {:ok, output}
    else
      :error
    end
  end

  defp snapshot_output(%{result: result}), do: result
  defp snapshot_output(_), do: nil
end
