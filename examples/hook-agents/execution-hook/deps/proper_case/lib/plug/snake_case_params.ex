defmodule ProperCase.Plug.SnakeCaseParams do
  @moduledoc """
  A helpful plug that converts your incoming parameters to
  Elixir's `snake_case`

  Plug it into your `router.ex` connection pipeline like so:
  ```
    pipeline :api do
      plug :accepts, ["json"]
      plug ProperCase.Plug.SnakeCaseParams
    end
  ```
  """

  def init(opts), do: opts

  def call(%{params: params} = conn, _opts) do
    %{conn | params: ProperCase.to_snake_case(params)}
  end
end
