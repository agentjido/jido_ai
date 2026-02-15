defmodule Jido.AI.LLMClient do
  @moduledoc """
  Configurable boundary for LLM provider calls.

  Actions and directives should call this module instead of `ReqLLM` directly.
  The default client is `Jido.AI.LLMClient.ReqLLM`, and tests can inject a
  deterministic client via context (`%{llm_client: MyClient}`) or application env.
  """

  @type model_spec :: String.t()
  @type messages :: [map()]
  @type opts :: keyword()
  @type context :: map() | keyword() | nil

  @callback generate_text(model_spec(), messages(), opts()) :: {:ok, map()} | {:error, term()}
  @callback stream_text(model_spec(), messages(), opts()) :: {:ok, term()} | {:error, term()}
  @callback process_stream(term(), opts()) :: {:ok, map()} | {:error, term()}

  @default_client Jido.AI.LLMClient.ReqLLM

  @spec generate_text(context(), model_spec(), messages(), opts()) :: {:ok, map()} | {:error, term()}
  def generate_text(context, model, messages, opts \\ []) do
    client_module(context).generate_text(model, messages, opts)
  end

  @spec stream_text(context(), model_spec(), messages(), opts()) :: {:ok, term()} | {:error, term()}
  def stream_text(context, model, messages, opts \\ []) do
    client_module(context).stream_text(model, messages, opts)
  end

  @spec process_stream(context(), term(), opts()) :: {:ok, map()} | {:error, term()}
  def process_stream(context, stream_response, opts \\ []) do
    client_module(context).process_stream(stream_response, opts)
  end

  @spec client_module(context()) :: module()
  def client_module(context \\ nil) do
    from_context(context) ||
      Application.get_env(:jido_ai, :llm_client, @default_client)
  end

  defp from_context(%{} = context), do: Map.get(context, :llm_client)

  defp from_context(context) when is_list(context) do
    Keyword.get(context, :llm_client)
  end

  defp from_context(_), do: nil
end
