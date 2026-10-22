defmodule Jido.AI.TestSupport.StreamResponseFactory do
  @moduledoc false

  def build(chunks, metadata \\ %{}, model_spec) when is_list(chunks) and is_map(metadata) do
    model = resolve_model(model_spec)
    {:ok, metadata_handle} = ReqLLM.StreamResponse.MetadataHandle.start_link(fn -> metadata end)

    %ReqLLM.StreamResponse{
      stream: chunks,
      metadata_handle: metadata_handle,
      cancel: fn -> :ok end,
      model: model,
      context: ReqLLM.Context.new([])
    }
  end

  defp resolve_model(%LLMDB.Model{} = model), do: model

  defp resolve_model(model_spec) do
    case ReqLLM.model(model_spec) do
      {:ok, model} ->
        model

      {:error, _reason} ->
        fallback_model(model_spec)
    end
  end

  defp fallback_model(model_spec) do
    model_id = normalize_model_id(model_spec)

    LLMDB.Model.new!(%{
      id: model_id,
      model: model_id,
      provider: infer_provider(model_spec)
    })
  end

  defp infer_provider(model_spec) when is_binary(model_spec) do
    model_spec
    |> String.split(":", parts: 2)
    |> List.first()
    |> String.to_atom()
  end

  defp infer_provider(model_spec) when is_atom(model_spec), do: model_spec
  defp infer_provider(_model_spec), do: :test

  defp normalize_model_id(model_spec) when is_binary(model_spec), do: model_spec
  defp normalize_model_id(model_spec) when is_atom(model_spec), do: Atom.to_string(model_spec)
  defp normalize_model_id(model_spec), do: inspect(model_spec)
end
