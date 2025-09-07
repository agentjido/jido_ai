defmodule ReqLLM.Capabilities.GenerateText do
  @moduledoc """
  Generate text capability verification for AI models.

  Verifies that a model can perform basic text generation by sending
  a simple message and validating the response.
  """

  @behaviour ReqLLM.Capability

  @impl true
  def id, do: :generate_text

  @impl true
  def advertised?(_model) do
    # Generate text is considered a basic capability available for all models
    true
  end

  @impl true
  def verify(model, opts) do
    model_spec = "#{model.provider}:#{model.model}"
    timeout = Keyword.get(opts, :timeout, 10_000)

    # Use provider_options to pass timeout to the HTTP client
    req_llm_opts = [
      provider_options: %{
        receive_timeout: timeout,
        timeout: timeout
      }
    ]

    case ReqLLM.generate_text(model_spec, "Hello!", req_llm_opts) do
      {:ok, %Req.Response{body: response}} when is_binary(response) ->
        trimmed = String.trim(response)

        if trimmed != "" do
          {:ok,
           %{
             model_id: model_spec,
             response_length: String.length(response),
             response_preview: String.slice(response, 0, 50)
           }}
        else
          {:error, "Empty response"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
