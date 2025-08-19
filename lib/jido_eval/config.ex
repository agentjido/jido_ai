defmodule Jido.Eval.Config do
  @moduledoc """
  Runtime configuration for Jido Eval.

  Central configuration struct that defines evaluation behavior including
  reporting, storage, broadcasting, processing, and middleware components.

  ## Examples

      iex> config = %Jido.Eval.Config{}
      iex> config.run_config.max_workers
      16
      
      iex> config = %Jido.Eval.Config{
      ...>   run_config: %Jido.Eval.RunConfig{max_workers: 8},
      ...>   tags: %{"experiment" => "test_run"}
      ...> }
      iex> config.tags
      %{"experiment" => "test_run"}
  """

  use TypedStruct

  typedstruct do
    @typedoc "Runtime configuration for Jido Eval"

    field(:run_id, String.t() | nil, default: nil)
    field(:run_config, Jido.Eval.RunConfig.t(), default: %Jido.Eval.RunConfig{})
    field(:model_spec, String.t(), default: "openai:gpt-4o")
    field(:reporters, [{module(), keyword()}], default: [{Jido.Eval.Reporter.Console, []}])
    field(:stores, [{module(), keyword()}], default: [])

    field(:broadcasters, [{module(), keyword()}],
      default: [{Jido.Eval.Broadcaster.Telemetry, [prefix: [:jido, :eval]]}]
    )

    field(:processors, [{module(), :pre | :post, keyword()}], default: [])
    field(:middleware, [module()], default: [Jido.Eval.Middleware.Tracing])
    field(:tags, %{String.t() => String.t()}, default: %{})
    field(:notes, String.t(), default: "")
  end

  @doc """
  Generates a new UUID for run_id if not set.

  ## Examples

      iex> config = %Jido.Eval.Config{run_id: "test-id"}
      iex> {:ok, updated} = Jido.Eval.Config.ensure_run_id(config)
      iex> updated.run_id
      "test-id"
      
      iex> config = %Jido.Eval.Config{run_id: nil}
      iex> {:ok, updated} = Jido.Eval.Config.ensure_run_id(config)
      iex> is_binary(updated.run_id)
      true
  """
  @spec ensure_run_id(t()) :: {:ok, t()}
  def ensure_run_id(%__MODULE__{run_id: nil} = config) do
    run_id = generate_uuid()
    run_config = %{config.run_config | run_id: run_id}
    {:ok, %{config | run_id: run_id, run_config: run_config}}
  end

  def ensure_run_id(%__MODULE__{run_id: run_id} = config) when is_binary(run_id) do
    run_config = %{config.run_config | run_id: run_id}
    {:ok, %{config | run_config: run_config}}
  end

  defp generate_uuid do
    Uniq.UUID.uuid7()
  end
end
