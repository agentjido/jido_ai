defmodule Jido.AI.Skill.Diagnostics do
  @moduledoc """
  Tracks parsing and loading warnings for skill diagnostics.

  Diagnostics capture non-fatal issues encountered during skill loading,
  including:
  - Parent directory name mismatches
  - Cosmetic naming violations
  - Truncated fields
  - Missing optional metadata

  Diagnostics enable tooling to display warnings to users without
  blocking skill functionality.

  ## Usage

      # Create fresh diagnostics
      diagnostics = Diagnostics.new()

      # Add a warning
      diagnostics = Diagnostics.add_warning(diagnostics, Diagnostics.Warning.new(:name_mismatch, "..."))

      # Check for issues
      Diagnostics.has_warnings?(diagnostics)
      Diagnostics.has_errors?(diagnostics)

      # Convert to map for storage
      Diagnostics.to_map(diagnostics)
  """

  defmodule Warning do
    @moduledoc """
    Represents a single diagnostic warning.
    """

    defstruct [:type, :message, :severity, :timestamp]

    @type t :: %__MODULE__{
            type: atom(),
            message: String.t(),
            severity: :low | :medium | :high,
            timestamp: DateTime.t()
          }

    @doc """
    Creates a new warning.

    ## Options

    - `:severity` - One of `:low`, `:medium`, `:high` (default: `:low`)
    """
    @spec new(atom(), String.t(), keyword()) :: t()
    def new(type, message, opts \\ []) do
      severity = Keyword.get(opts, :severity, :low)

      %__MODULE__{
        type: type,
        message: message,
        severity: severity,
        timestamp: DateTime.utc_now()
      }
    end

    @doc """
    Converts warning to a plain map.
    """
    @spec to_map(t()) :: map()
    def to_map(%__MODULE__{} = warning) do
      %{
        type: warning.type,
        message: warning.message,
        severity: warning.severity,
        timestamp: DateTime.to_iso8601(warning.timestamp)
      }
    end

    @doc """
    Formats warning for display.
    """
    @spec format(t()) :: String.t()
    def format(%__MODULE__{} = warning) do
      "[#{warning.severity}] #{warning.type}: #{warning.message}"
    end
  end

  defstruct warnings: [], errors: [], timestamp: nil

  @type t :: %__MODULE__{
          warnings: [Warning.t()],
          errors: [map()],
          timestamp: DateTime.t() | nil
        }

  @doc """
  Creates a new empty diagnostics struct.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      warnings: [],
      errors: [],
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Adds a warning to the diagnostics.
  """
  @spec add_warning(t(), Warning.t()) :: t()
  def add_warning(%__MODULE__{} = diag, %Warning{} = warning) do
    %{diag | warnings: [warning | diag.warnings]}
  end

  @doc """
  Adds an error to the diagnostics (non-fatal in lenient mode).
  """
  @spec add_error(t(), map()) :: t()
  def add_error(%__MODULE__{} = diag, error) do
    %{diag | errors: [error | diag.errors]}
  end

  @doc """
  Returns true if there are any warnings.
  """
  @spec has_warnings?(t()) :: boolean()
  def has_warnings?(%__MODULE__{warnings: warnings}), do: warnings != []

  @doc """
  Returns true if there are any errors.
  """
  @spec has_errors?(t()) :: boolean()
  def has_errors?(%__MODULE__{errors: errors}), do: errors != []

  @doc """
  Returns true if there are any warnings or errors.
  """
  @spec has_issues?(t()) :: boolean()
  def has_issues?(%__MODULE__{} = diag), do: has_warnings?(diag) or has_errors?(diag)

  @doc """
  Returns the count of warnings.
  """
  @spec warning_count(t()) :: non_neg_integer()
  def warning_count(%__MODULE__{warnings: warnings}), do: length(warnings)

  @doc """
  Returns the count of errors.
  """
  @spec error_count(t()) :: non_neg_integer()
  def error_count(%__MODULE__{errors: errors}), do: length(errors)

  @doc """
  Converts diagnostics to a plain map for storage in metadata.
  """
  @spec to_map(t() | nil) :: map() | nil
  def to_map(nil), do: nil

  def to_map(%__MODULE__{} = diag) do
    %{
      warning_count: warning_count(diag),
      error_count: error_count(diag),
      warnings: Enum.map(diag.warnings, &Warning.to_map/1),
      errors: Enum.map(diag.errors, &error_to_map/1),
      timestamp: diag.timestamp && DateTime.to_iso8601(diag.timestamp)
    }
  end

  @doc """
  Formats diagnostics for display in logs or tooling.
  """
  @spec format(t() | nil) :: String.t()
  def format(nil), do: "No diagnostics"

  def format(%__MODULE__{} = diag) do
    lines = []

    lines =
      if has_warnings?(diag) do
        lines ++ ["Warnings (#{warning_count(diag)}):" | Enum.map(diag.warnings, &"  - #{Warning.format(&1)}")]
      else
        lines
      end

    lines =
      if has_errors?(diag) do
        lines ++ ["Errors (#{error_count(diag)}):" | Enum.map(diag.errors, &"  - #{format_error(&1)}")]
      else
        lines
      end

    if lines == [], do: "No diagnostics", else: Enum.join(lines, "\n")
  end

  defp error_to_map(error) when is_struct(error) do
    Map.from_struct(error)
  end

  defp error_to_map(error), do: %{error: inspect(error)}

  defp format_error(error) when is_struct(error) do
    if function_exported?(error.__struct__, :message, 1) do
      error.__struct__.message(error)
    else
      inspect(error)
    end
  end

  defp format_error(error), do: inspect(error)
end
