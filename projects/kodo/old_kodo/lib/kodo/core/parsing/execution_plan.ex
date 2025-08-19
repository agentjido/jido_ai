defmodule Kodo.Core.Parsing.ExecutionPlan do
  @moduledoc """
  Data structures for representing parsed shell command execution plans.
  Supports pipes, redirections, and control operators.
  """

  defstruct [:pipelines, :control_ops]

  @type t :: %__MODULE__{
          pipelines: [Pipeline.t()],
          control_ops: [control_op()]
        }

  @type control_op :: :and | :or | :semicolon | :background

  defmodule Pipeline do
    @moduledoc """
    Represents a pipeline of commands connected by pipes (|).
    """

    defstruct [:commands, :background?]

    @type t :: %__MODULE__{
            commands: [Command.t()],
            background?: boolean()
          }
  end

  defmodule Command do
    @moduledoc """
    Represents a single command with its arguments and redirections.
    """

    defstruct [:name, :args, :redirections, :env]

    @type t :: %__MODULE__{
            name: String.t(),
            args: [String.t()],
            redirections: [Redirection.t()],
            env: %{String.t() => String.t()} | nil
          }
  end

  defmodule Redirection do
    @moduledoc """
    Represents input/output redirection for a command.
    """

    defstruct [:type, :target]

    @type redirection_type :: :input | :output | :append

    @type t :: %__MODULE__{
            type: redirection_type(),
            target: String.t()
          }
  end

  @doc """
  Get all commands from an execution plan, flattening pipelines.
  """
  @spec get_all_commands(t()) :: [Command.t()]
  def get_all_commands(%__MODULE__{pipelines: pipelines}) do
    pipelines
    |> Enum.flat_map(fn %Pipeline{commands: commands} -> commands end)
  end

  @doc """
  Check if the execution plan contains any background processes.
  """
  @spec has_background_process?(t()) :: boolean()
  def has_background_process?(%__MODULE__{pipelines: pipelines, control_ops: control_ops}) do
    has_background_pipeline =
      Enum.any?(pipelines, fn %Pipeline{background?: background?} ->
        background? == true
      end)

    has_background_op = Enum.any?(control_ops, fn op -> op == :background end)

    has_background_pipeline or has_background_op
  end

  @doc """
  Get all pipelines from the execution plan.
  """
  @spec get_pipelines(t()) :: [Pipeline.t()]
  def get_pipelines(%__MODULE__{pipelines: pipelines}) do
    pipelines
  end

  @doc """
  Check if a command has any redirections of the specified type.
  """
  @spec has_redirection?(Command.t(), Redirection.redirection_type()) :: boolean()
  def has_redirection?(%Command{redirections: redirections}, type) do
    Enum.any?(redirections, fn %Redirection{type: redir_type} ->
      redir_type == type
    end)
  end

  @doc """
  Get redirections of a specific type from a command.
  """
  @spec get_redirections(Command.t(), Redirection.redirection_type()) :: [Redirection.t()]
  def get_redirections(%Command{redirections: redirections}, type) do
    Enum.filter(redirections, fn %Redirection{type: redir_type} ->
      redir_type == type
    end)
  end
end
