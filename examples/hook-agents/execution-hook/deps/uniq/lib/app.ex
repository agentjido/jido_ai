defmodule Uniq.App do
  @moduledoc false
  use Application

  def start(_type, _args) do
    children = [
      Uniq.Generator
    ]

    Supervisor.start_link(children, strategy: :rest_for_one)
  end
end
