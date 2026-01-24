defmodule Jido.AI.GEPA.Helpers do
  @moduledoc """
  Shared helper functions for GEPA modules.

  This module contains common utilities used across multiple GEPA components
  to avoid code duplication.
  """

  @type runner_fn :: (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()})

  @doc """
  Validates that the required runner option is present and is a valid function.

  ## Parameters

  - `opts` - Keyword list of options

  ## Returns

  - `:ok` if runner is valid
  - `{:error, :runner_required}` if runner is missing
  - `{:error, :invalid_runner}` if runner is not a 3-arity function

  ## Examples

      iex> Helpers.validate_runner_opts(runner: fn _, _, _ -> :ok end)
      :ok

      iex> Helpers.validate_runner_opts([])
      {:error, :runner_required}

      iex> Helpers.validate_runner_opts(runner: fn -> :ok end)
      {:error, :invalid_runner}
  """
  @spec validate_runner_opts(keyword()) :: :ok | {:error, :runner_required | :invalid_runner}
  def validate_runner_opts(opts) do
    cond do
      not Keyword.has_key?(opts, :runner) -> {:error, :runner_required}
      not is_function(Keyword.get(opts, :runner), 3) -> {:error, :invalid_runner}
      true -> :ok
    end
  end
end
