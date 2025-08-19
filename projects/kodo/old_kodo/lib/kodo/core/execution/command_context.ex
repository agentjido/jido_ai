defmodule Kodo.Core.Execution.CommandContext do
  @moduledoc """
  Enhanced command execution context that supports job control,
  stdio management, and pipeline execution.

  This extends the original context with additional fields needed
  for Phase 3 job control and pipeline execution features.
  """

  defstruct [
    # Session identifier (string)
    :session_id,
    # Session process PID (for backwards compatibility)
    :session_pid,
    # Environment variables map
    :env,
    # Current working directory (was current_dir)
    :working_dir,
    # Input stream specification
    :stdin,
    # Output stream specification
    :stdout,
    # Error stream specification
    :stderr,
    # Associated job ID (if any)
    :job_id,
    # Background execution flag
    :background?,
    # Additional options map
    :opts
  ]

  @type stream_spec :: :inherit | :pipe | :capture | {:file, String.t(), [atom()]}

  @type t :: %__MODULE__{
          session_id: String.t(),
          session_pid: pid(),
          env: map(),
          working_dir: String.t(),
          stdin: stream_spec(),
          stdout: stream_spec(),
          stderr: stream_spec(),
          job_id: pos_integer() | nil,
          background?: boolean(),
          opts: map()
        }

  @doc """
  Creates a new command context with the given parameters.
  """
  @spec new(String.t(), pid(), map()) :: t()
  def new(session_id, session_pid, opts \\ %{}) do
    %__MODULE__{
      session_id: session_id,
      session_pid: session_pid,
      env: Map.get(opts, :env, %{}),
      working_dir: Map.get(opts, :working_dir, File.cwd!()),
      stdin: Map.get(opts, :stdin, :inherit),
      stdout: Map.get(opts, :stdout, :inherit),
      stderr: Map.get(opts, :stderr, :inherit),
      job_id: Map.get(opts, :job_id),
      background?: Map.get(opts, :background?, false),
      opts: Map.drop(opts, [:env, :working_dir, :stdin, :stdout, :stderr, :job_id, :background?])
    }
  end

  @doc """
  Creates a command context from the legacy context format.
  This provides backwards compatibility with existing commands.
  """
  @spec from_legacy(map()) :: t()
  def from_legacy(%{session_pid: session_pid} = legacy_context) do
    # Extract session_id from the session_pid if possible
    # For now, we'll use a simple string representation
    session_id = legacy_context[:session_id] || "session_#{:erlang.phash2(session_pid)}"

    %__MODULE__{
      session_id: session_id,
      session_pid: session_pid,
      env: Map.get(legacy_context, :env, %{}),
      working_dir: Map.get(legacy_context, :current_dir, File.cwd!()),
      stdin: :inherit,
      stdout: :inherit,
      stderr: :inherit,
      job_id: nil,
      background?: false,
      opts: Map.get(legacy_context, :opts, %{})
    }
  end

  @doc """
  Converts the context to the legacy format for backwards compatibility.
  """
  @spec to_legacy(t()) :: map()
  def to_legacy(%__MODULE__{} = context) do
    %{
      session_pid: context.session_pid,
      env: context.env,
      current_dir: context.working_dir,
      opts: context.opts
    }
  end

  @doc """
  Sets the job ID for this context.
  """
  @spec set_job_id(t(), pos_integer()) :: t()
  def set_job_id(%__MODULE__{} = context, job_id) when is_integer(job_id) do
    %{context | job_id: job_id}
  end

  @doc """
  Marks the context as background execution.
  """
  @spec set_background(t(), boolean()) :: t()
  def set_background(%__MODULE__{} = context, background?) when is_boolean(background?) do
    %{context | background?: background?}
  end

  @doc """
  Sets the stdio streams for the context.
  """
  @spec set_stdio(t(), stream_spec(), stream_spec(), stream_spec()) :: t()
  def set_stdio(%__MODULE__{} = context, stdin, stdout, stderr) do
    %{context | stdin: stdin, stdout: stdout, stderr: stderr}
  end

  @doc """
  Updates the working directory.
  """
  @spec set_working_dir(t(), String.t()) :: t()
  def set_working_dir(%__MODULE__{} = context, working_dir) when is_binary(working_dir) do
    %{context | working_dir: working_dir}
  end

  @doc """
  Updates environment variables.
  """
  @spec update_env(t(), map()) :: t()
  def update_env(%__MODULE__{} = context, env_updates) when is_map(env_updates) do
    new_env = Map.merge(context.env, env_updates)
    %{context | env: new_env}
  end

  @doc """
  Sets a single environment variable.
  """
  @spec put_env(t(), String.t(), String.t()) :: t()
  def put_env(%__MODULE__{} = context, key, value) when is_binary(key) and is_binary(value) do
    new_env = Map.put(context.env, key, value)
    %{context | env: new_env}
  end

  @doc """
  Gets an environment variable value.
  """
  @spec get_env(t(), String.t(), String.t() | nil) :: String.t() | nil
  def get_env(%__MODULE__{} = context, key, default \\ nil) do
    Map.get(context.env, key, default)
  end

  @doc """
  Checks if this context represents a background job.
  """
  @spec background?(t()) :: boolean()
  def background?(%__MODULE__{background?: background?}), do: background?

  @doc """
  Checks if this context has stdio redirection.
  """
  @spec has_stdio_redirection?(t()) :: boolean()
  def has_stdio_redirection?(%__MODULE__{} = context) do
    context.stdin != :inherit or
      context.stdout != :inherit or
      context.stderr != :inherit
  end

  @doc """
  Creates a context for capturing command output (useful for testing).
  """
  @spec capture_output(t()) :: t()
  def capture_output(%__MODULE__{} = context) do
    %{context | stdin: :pipe, stdout: :capture, stderr: :capture}
  end

  @doc """
  Creates a context for background execution with proper stdio handling.
  """
  @spec background_context(t()) :: t()
  def background_context(%__MODULE__{} = context) do
    %{
      context
      | background?: true,
        stdin: {:file, "/dev/null", [:read]},
        stdout: {:file, "/dev/null", [:write]},
        stderr: {:file, "/dev/null", [:write]}
    }
  end
end
