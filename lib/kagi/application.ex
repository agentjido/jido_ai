defmodule Kagi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    configure_log_filter()

    children = [
      Kagi.Server
    ]

    opts = [strategy: :one_for_one, name: Kagi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc false
  @spec configure_log_filter() :: :ok
  defp configure_log_filter do
    if Application.get_env(:kagi, Kagi.LogFilter, []) |> Keyword.get(:enabled, true) do
      :logger.add_primary_filter(:kagi_log_filter, {&Kagi.LogFilter.filter/2, []})
    end

    :ok
  end
end
