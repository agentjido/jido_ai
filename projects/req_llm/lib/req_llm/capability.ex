defmodule ReqLLM.Capability do
  @moduledoc """
  Behaviour for defining verifiable AI model capabilities.

  Each capability module implements this behaviour to provide verification
  logic for a specific AI feature (generate_text, tools, streaming, etc.).

  ## Examples

      defmodule ReqLLM.Capabilities.GenerateText do
        @behaviour ReqLLM.Capability

        @impl true
        def id, do: :generate_text

        @impl true
        def advertised?(_metadata), do: true

        @impl true
        def verify(metadata, opts) do
          with {:ok, response} <- ReqLLM.generate_text(metadata.id, "Hello!", opts),
               true <- String.trim(response) != "" or {:error, :empty} do
            {:ok, %{response_length: String.length(response)}}
          end
        end
      end

  """

  @doc """
  Returns the unique identifier for this capability.

  Should be a descriptive atom like `:generate_text`, `:tools`, `:stream`, etc.
  """
  @callback id() :: atom()

  @doc """
  Determines if this capability is advertised by the given model.

  Return `true` if the model claims to support this capability and it should
  be verified, `false` otherwise.

  ## Parameters

    * `model` - The ReqLLM.Model struct with metadata

  """
  @callback advertised?(ReqLLM.Model.t()) :: boolean()

  @doc """
  Verifies that the capability works correctly with the given model.

  Should make actual API calls using ReqLLM's public interface and return
  `{:ok, details}` on success or `{:error, reason}` on failure.

  ## Parameters

    * `model` - The ReqLLM.Model struct with metadata
    * `opts` - Additional options including timeout, etc.

  """
  @callback verify(ReqLLM.Model.t(), keyword()) :: {:ok, term()} | {:error, term()}
end
