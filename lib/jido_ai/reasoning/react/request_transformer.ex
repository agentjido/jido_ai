defmodule Jido.AI.Reasoning.ReAct.RequestTransformer do
  @moduledoc """
  Behavior for advanced per-turn ReAct request shaping.

  A request transformer can inspect the current runtime state and tool context
  before each LLM turn, then return request overrides.

  This is intended for patterns such as:

  - request-scoped tool gating
  - dynamic structured-output schemas
  - provider-specific `llm_opts` based on tool results
  - custom message projection beyond the default context rendering

  The runtime always regenerates `llm_opts[:tools]` from the returned `tools`
  field so the exposed LLM tools and execution registry stay aligned.
  """

  alias Jido.AI.Reasoning.ReAct.{Config, State, ToolSelection}

  @type request :: %{
          required(:messages) => [map()],
          required(:llm_opts) => keyword(),
          required(:tools) => ToolSelection.tools_input()
        }

  @type overrides :: %{
          optional(:messages) => [map()],
          optional(:llm_opts) => keyword() | map(),
          optional(:tools) => ToolSelection.tools_input()
        }

  @doc """
  Validate a request transformer module.
  """
  @spec validate(module() | nil) ::
          {:ok, module() | nil}
          | {:error, :invalid_request_transformer}
          | {:error, {:request_transformer_not_loaded, module()}}
          | {:error, {:request_transformer_missing_callback, module()}}
  def validate(nil), do: {:ok, nil}

  def validate(module) when is_atom(module) do
    cond do
      not Code.ensure_loaded?(module) ->
        {:error, {:request_transformer_not_loaded, module}}

      not function_exported?(module, :transform_request, 4) ->
        {:error, {:request_transformer_missing_callback, module}}

      true ->
        {:ok, module}
    end
  end

  def validate(_other), do: {:error, :invalid_request_transformer}

  @doc """
  Fingerprint a validated transformer for checkpoint compatibility.
  """
  @spec fingerprint(module() | nil) :: String.t()
  def fingerprint(nil), do: ""
  def fingerprint(module) when is_atom(module), do: Atom.to_string(module)

  @callback transform_request(request(), State.t(), Config.t(), map()) ::
              {:ok, overrides()} | {:error, term()}
end
