defmodule Kodo.Ports.Command do
  @moduledoc """
  Behavior defining the interface for shell commands.
  """

  @type args :: [String.t()]
  @type context :: %{
          session_pid: pid(),
          env: map(),
          current_dir: String.t(),
          opts: map()
        }
  @type result :: {:ok, String.t()} | {:error, String.t()}
  @type meta_flag :: :builtin | :pure | :changes_dir

  @callback name() :: String.t()
  @callback description() :: String.t()
  @callback usage() :: String.t()
  @callback meta() :: [meta_flag()]
  @callback execute(args(), context()) :: result()
end
