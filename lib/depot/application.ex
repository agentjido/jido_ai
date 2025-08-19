defmodule Depot.Application do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      Depot.Registry
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
