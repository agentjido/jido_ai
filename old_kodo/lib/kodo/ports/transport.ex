defmodule Kodo.Ports.Transport do
  @moduledoc """
  Behavior defining the interface for shell transports.
  """

  @type options :: keyword()
  @type result :: {:ok, pid()} | {:error, term()}

  @callback start_link(options()) :: result()
  @callback stop(pid()) :: :ok
  @callback write(pid(), String.t()) :: :ok
end
