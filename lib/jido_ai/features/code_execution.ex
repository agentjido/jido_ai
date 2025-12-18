defmodule Jido.AI.Features.CodeExecution do
  @moduledoc """
  Code execution capabilities for supported models.

  **⚠️  SECURITY WARNING ⚠️**

  Code execution is DISABLED by default and requires explicit opt-in.
  Never enable code execution with untrusted input or in production
  environments without proper sandboxing.

  ## Supported Providers

  - **OpenAI**: Code Interpreter via Assistants API (GPT-4, GPT-3.5)

  ## Security Model

  Code execution is disabled by default. To enable:

  1. Set `enable_code_execution: true` in options
  2. Understand the security implications
  3. Use only in controlled environments
  4. Consider external sandboxing (Docker, VMs)

  ## Usage

      # Check support (does not enable)
      CodeExecution.supports?(model)

      # Enable code execution (requires explicit opt-in)
      opts = CodeExecution.build_code_exec_options(
        base_opts,
        model.provider,
        enable: true
      )

  ## Architecture

  This module provides:
  - Feature detection for code execution support
  - Options builder for enabling code interpreter
  - Result extraction from code execution outputs
  - Security safeguards and warnings

  The actual code execution happens on the provider's infrastructure
  (e.g., OpenAI's sandboxed environment). This module does not execute
  code locally.
  """

  alias Jido.AI.Model
  require Logger

  @type code_result :: %{
          input: String.t(),
          output: String.t(),
          logs: [String.t()],
          files: [String.t()]
        }

  @doc """
  Check if a model supports code execution.

  ## Parameters
    - model: Jido.AI.Model struct

  ## Returns
    Boolean indicating code execution support

  ## Examples

      iex> CodeExecution.supports?(model)
      true  # For OpenAI GPT-4 models
  """
  @spec supports?(Model.t()) :: boolean()
  def supports?(%Model{provider: :openai, model: model_id}) do
    # OpenAI supports code execution via Assistants API for GPT-4 and GPT-3.5
    String.contains?(model_id, "gpt-4") or String.contains?(model_id, "gpt-3.5")
  end

  def supports?(_model), do: false

  @doc """
  Build options for code execution-enabled completion.

  **⚠️  Security Warning**: This enables code execution. Use with caution.

  ## Parameters
    - base_opts: Base options map
    - provider: Provider atom
    - opts: Keyword list with `:enable` flag

  ## Options
    - `:enable` - Must be `true` to enable code execution (default: false)
    - `:timeout` - Execution timeout in seconds (default: 30)
    - `:allow_network` - Allow network access (provider-dependent)

  ## Returns
    - `{:ok, enhanced_opts}` with code execution enabled
    - `{:error, :not_enabled}` if not explicitly enabled
    - `{:error, :unsupported}` if provider doesn't support it

  ## Examples

      iex> CodeExecution.build_code_exec_options(opts, :openai, enable: true)
      {:ok, %{...tools: [%{type: "code_interpreter"}]}}
  """
  @spec build_code_exec_options(map(), atom(), keyword()) ::
          {:ok, map()} | {:error, atom()}
  def build_code_exec_options(base_opts, provider, opts \\ []) do
    enable = Keyword.get(opts, :enable, false)

    cond do
      not enable ->
        Logger.warning("""
        Code execution requested but not explicitly enabled.
        Set `enable: true` to enable code execution.
        """)

        {:error, :not_enabled}

      provider == :openai ->
        Logger.warning("""
        Code execution ENABLED. This allows the model to execute code.
        Use only in controlled environments with trusted input.
        """)

        enhanced_opts =
          base_opts
          |> Map.put(:tools, [%{type: "code_interpreter"}])
          |> maybe_add_timeout(opts)

        {:ok, enhanced_opts}

      true ->
        {:error, :unsupported}
    end
  end

  @doc """
  Extract code execution results from a completion response.

  Parses code execution outputs from provider-specific response formats.

  ## Parameters
    - response: Raw response from provider
    - provider: Provider atom

  ## Returns
    - `{:ok, [code_results]}` with execution results
    - `{:ok, []}` if no code was executed
    - `{:error, reason}` on failure

  ## Examples

      iex> CodeExecution.extract_results(response, :openai)
      {:ok, [%{input: "print('hello')", output: "hello", logs: [], files: []}]}
  """
  @spec extract_results(map(), atom()) :: {:ok, [code_result()]} | {:error, term()}
  def extract_results(%{"tool_calls" => tool_calls}, :openai) when is_list(tool_calls) do
    code_results =
      tool_calls
      |> Enum.filter(fn call -> Map.get(call, "type") == "code_interpreter" end)
      |> Enum.map(&extract_openai_code_result/1)

    {:ok, code_results}
  end

  def extract_results(_response, :openai) do
    # No code execution in response
    {:ok, []}
  end

  def extract_results(_response, _provider) do
    {:ok, []}
  end

  @doc """
  Check if code execution is safe to enable in current environment.

  Performs basic safety checks (not comprehensive security audit).

  ## Returns
    - `{:ok, :safe}` if basic checks pass
    - `{:error, reasons}` with list of concerns

  ## Examples

      iex> CodeExecution.safety_check()
      {:ok, :safe}
  """
  @spec safety_check() :: {:ok, :safe} | {:error, [String.t()]}
  def safety_check do
    concerns = []

    concerns =
      if Mix.env() == :prod do
        ["Running in production environment" | concerns]
      else
        concerns
      end

    # Add more safety checks here
    # - Check if running in container
    # - Check if network is isolated
    # - Check if filesystem is sandboxed

    if Enum.empty?(concerns) do
      {:ok, :safe}
    else
      {:error, concerns}
    end
  end

  # Private helpers

  defp extract_openai_code_result(tool_call) do
    code_interpreter = Map.get(tool_call, "code_interpreter", %{})

    %{
      input: Map.get(code_interpreter, "input", ""),
      output: Map.get(code_interpreter, "output", ""),
      logs: Map.get(code_interpreter, "logs", []),
      files: Map.get(code_interpreter, "files", [])
    }
  end

  defp maybe_add_timeout(opts, kw_opts) do
    case Keyword.get(kw_opts, :timeout) do
      nil -> opts
      timeout -> Map.put(opts, :timeout, timeout)
    end
  end
end
