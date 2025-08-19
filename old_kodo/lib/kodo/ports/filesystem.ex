defmodule Kodo.Ports.FileSystem do
  @moduledoc """
  Port definition for filesystem operations with terse API.
  """

  @type path :: String.t()
  @type content :: iodata()
  @type opts :: keyword()
  @type result :: {:ok, term()} | {:error, term()}

  # Core file operations
  @callback write(path(), content(), opts()) :: result()
  @callback read(path(), opts()) :: result()
  @callback delete(path(), opts()) :: result()
  @callback copy(path(), path(), opts()) :: result()
  @callback move(path(), path(), opts()) :: result()

  # Directory operations - terse API
  @callback ls(path(), opts()) :: result()
  @callback exists?(path(), opts()) :: boolean()
  @callback mkdir(path(), opts()) :: result()
  @callback rmdir(path(), opts()) :: result()
  @callback clear(opts()) :: result()

  # Mount operations
  @callback mount(path(), module(), opts()) :: result()
  @callback unmount(path()) :: result()
  @callback mounts() :: result()
end
