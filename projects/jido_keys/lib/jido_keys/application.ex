defmodule JidoKeys.Application do
  @moduledoc """
  The JidoKeys application supervisor.

  This module starts the main JidoKeys.Server GenServer and configures
  the log filter for sensitive data redaction.
  """

  use Application

  @impl true
  def start(_type, _args) do
    configure_log_filter()

    children = [
      JidoKeys.Server
    ]

    opts = [strategy: :one_for_one, name: JidoKeys.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  @spec configure_log_filter() :: :ok
  defp configure_log_filter do
    if Application.get_env(:jido_keys, JidoKeys.LogFilter, []) |> Keyword.get(:enabled, true) do
      :logger.add_primary_filter(:jido_keys_log_filter, {&JidoKeys.LogFilter.filter/2, []})
    end

    :ok
  end
end
