defmodule Jido.Exec.Compensation do
  @moduledoc """
  Handles error compensation logic for Jido actions.

  This module provides functionality to execute compensation actions when
  an action fails, if the action implements the `on_error/4` callback and
  has compensation enabled in its metadata.
  """
  use Private

  alias Jido.Action.Error
  alias Jido.Exec.Telemetry

  require Logger

  @type action :: module()
  @type params :: map()
  @type context :: map()
  @type run_opts :: [timeout: non_neg_integer()]
  @type exec_result ::
          {:ok, map()}
          | {:ok, map(), any()}
          | {:error, Exception.t()}
          | {:error, Exception.t(), any()}

  @doc """
  Checks if compensation is enabled for the given action.

  Compensation is enabled if:
  1. The action's metadata includes compensation configuration with `enabled: true`
  2. The action exports the `on_error/4` function

  ## Parameters

  - `action`: The action module to check

  ## Returns

  - `true` if compensation is enabled and available
  - `false` otherwise
  """
  @spec enabled?(action()) :: boolean()
  def enabled?(action) do
    metadata = action.__action_metadata__()
    compensation_opts = metadata[:compensation] || []

    enabled =
      case compensation_opts do
        opts when is_list(opts) -> Keyword.get(opts, :enabled, false)
        %{enabled: enabled} -> enabled
        _ -> false
      end

    enabled && function_exported?(action, :on_error, 4)
  end

  @doc """
  Handles action errors by executing compensation if enabled.

  This is the main entry point for error handling with compensation.
  If compensation is enabled, it will execute the action's `on_error/4` callback
  within a timeout. If compensation is disabled, it returns the original error.

  ## Parameters

  - `action`: The action module that failed
  - `params`: The parameters that were passed to the action
  - `context`: The context that was passed to the action
  - `error_or_tuple`: The error from the failed action, either an Exception or {Exception, directive}
  - `opts`: Execution options including timeout

  ## Returns

  - `{:error, compensated_error}` or `{:error, compensated_error, directive}` if compensation was attempted
  - `{:error, original_error}` or `{:error, original_error, directive}` if compensation is disabled
  """
  @spec handle_error(
          action(),
          params(),
          context(),
          Exception.t() | {Exception.t(), any()},
          run_opts()
        ) :: exec_result
  def handle_error(action, params, context, error_or_tuple, opts) do
    Logger.debug("Handle Action Error in handle_error: #{inspect(opts)}")
    # Extract error and directive if present
    {error, directive} =
      case error_or_tuple do
        {error, directive} -> {error, directive}
        error -> {error, nil}
      end

    if enabled?(action) do
      execute_compensation(action, params, context, error, directive, opts)
    else
      if directive, do: {:error, error, directive}, else: {:error, error}
    end
  end

  # Private functions are exposed to the test suite
  private do
    @spec execute_compensation(action(), params(), context(), Exception.t(), any(), run_opts()) ::
            exec_result
    defp execute_compensation(action, params, context, error, directive, opts) do
      metadata = action.__action_metadata__()
      compensation_opts = metadata[:compensation] || []

      timeout =
        Keyword.get(opts, :timeout) ||
          case compensation_opts do
            opts when is_list(opts) -> Keyword.get(opts, :timeout, 5_000)
            %{timeout: timeout} -> timeout
            _ -> 5_000
          end

      task =
        Task.async(fn ->
          action.on_error(params, error, context, [])
        end)

      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} ->
          handle_compensation_result(result, error, directive)

        nil ->
          error_result =
            Error.execution_error(
              "Compensation timed out after #{timeout}ms for: #{inspect(error)}",
              %{
                compensated: false,
                compensation_error: "Compensation timed out after #{timeout}ms",
                original_error: error
              }
            )

          if directive, do: {:error, error_result, directive}, else: {:error, error_result}
      end
    end

    @spec handle_compensation_result(any(), Exception.t(), any()) :: exec_result
    defp handle_compensation_result(result, original_error, directive) do
      error_result =
        case result do
          {:ok, comp_result} ->
            # Extract fields that should be at the top level of the details
            {top_level_fields, remaining_fields} =
              Map.split(comp_result, [:test_value, :compensation_context])

            # Create the details map with the compensation result
            details =
              Map.merge(
                %{
                  compensated: true,
                  compensation_result: remaining_fields
                },
                top_level_fields
              )

            # Extract message from error struct properly using safe helper
            error_message = Telemetry.extract_safe_error_message(original_error)

            Error.execution_error(
              "Compensation completed for: #{error_message}",
              Map.put(details, :original_error, original_error)
            )

          {:error, comp_error} ->
            # Extract message from error struct properly using safe helper
            error_message = Telemetry.extract_safe_error_message(original_error)

            Error.execution_error(
              "Compensation failed for: #{error_message}",
              %{
                compensated: false,
                compensation_error: comp_error,
                original_error: original_error
              }
            )

          _ ->
            Error.execution_error(
              "Invalid compensation result for: #{inspect(original_error)}",
              %{
                compensated: false,
                compensation_error: "Invalid compensation result",
                original_error: original_error
              }
            )
        end

      if directive, do: {:error, error_result, directive}, else: {:error, error_result}
    end
  end
end
