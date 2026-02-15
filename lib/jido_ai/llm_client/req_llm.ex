defmodule Jido.AI.LLMClient.ReqLLM do
  @moduledoc """
  Default `Jido.AI.LLMClient` implementation backed by `ReqLLM`.
  """

  @behaviour Jido.AI.LLMClient

  @impl true
  def generate_text(model, messages, opts) do
    ReqLLM.Generation.generate_text(model, messages, opts)
  end

  @impl true
  def stream_text(model, messages, opts) do
    ReqLLM.stream_text(model, messages, opts)
  end

  @impl true
  def process_stream(stream_response, opts) do
    ReqLLM.StreamResponse.process_stream(stream_response, opts)
  end
end
