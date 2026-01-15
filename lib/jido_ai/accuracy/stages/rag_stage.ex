defmodule Jido.AI.Accuracy.Stages.RAGStage do
  @moduledoc """
  Pipeline stage for RAG (Retrieval-Augmented Generation) with correction.

  This is an optional stage that retrieves context for the query and applies
  correction if retrieval quality is low. The retrieved context is passed
  to downstream stages for candidate generation.

  ## Configuration

  - `:enabled` - Whether RAG is enabled (default: true)
  - `:retriever` - The retriever module to use
  - `:apply_correction` - Whether to apply correction (default: true)
  - `:min_quality_threshold` - Minimum retrieval quality (default: 0.5)

  ## Output State

  Adds to the pipeline state:
  - `:context` - Retrieved context map or nil
  - `:rag_applied` - Whether RAG was successfully applied

  ## Usage

      stage = RAGStage.new(%{
        retriever: MyRetriever,
        apply_correction: true
      })

  """

  alias Jido.AI.Accuracy.PipelineStage

  @behaviour PipelineStage

  @type t :: %__MODULE__{
          enabled: boolean(),
          retriever: module() | nil,
          apply_correction: boolean(),
          min_quality_threshold: float()
        }

  defstruct [
    :retriever,
    enabled: true,
    apply_correction: true,
    min_quality_threshold: 0.5
  ]

  @impl PipelineStage
  def name, do: :rag

  @impl PipelineStage
  def required?, do: false

  @impl PipelineStage
  def execute(input, config) do
    enabled = Map.get(config, :enabled, true)

    unless enabled do
      # Stage disabled, skip
      {:ok, input, %{skipped: true}}
    else
      query = Map.get(input, :query)
      retriever = Map.get(config, :retriever)

      cond do
        is_binary(query) and query != "" and not is_nil(retriever) ->
          retrieve_and_correct(query, input, config)

        true ->
          # No retriever configured, skip
          {:ok, Map.put(input, :rag_applied, false), %{no_retriever: true}}
      end
    end
  end

  @doc """
  Creates a new stage configuration.

  """
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      retriever: Map.get(attrs, :retriever),
      enabled: Map.get(attrs, :enabled, true),
      apply_correction: Map.get(attrs, :apply_correction, true),
      min_quality_threshold: Map.get(attrs, :min_quality_threshold, 0.5)
    }
  end

  # Private functions

  defp retrieve_and_correct(query, input, config) do
    retriever = Map.get(config, :retriever)

    # Try to retrieve context
    case call_retrieve(retriever, query, input) do
      {:ok, context} when is_map(context) ->
        # Check if correction is needed
        apply_correction? = Map.get(config, :apply_correction, true)

        {final_context, corrected} =
          if apply_correction? do
            maybe_apply_correction(context, config)
          else
            {context, false}
          end

        updated_state =
          input
          |> Map.put(:context, final_context)
          |> Map.put(:rag_applied, true)
          |> Map.put(:rag_corrected, corrected)

        {:ok, updated_state, %{context_retrieved: true, corrected: corrected}}

      {:ok, nil} ->
        # No context retrieved
        {:ok, Map.put(input, :rag_applied, false), %{no_context: true}}

      {:error, _reason} ->
        # Retrieval failed, continue without context
        {:ok, Map.put(input, :rag_applied, false), %{retrieval_failed: true}}
    end
  end

  defp call_retrieve(retriever, query, input) do
    context = Map.get(input, :context, %{})

    cond do
      # Check if retriever has a retrieve/3 function
      function_exported?(retriever, :retrieve, 3) ->
        retriever.retrieve(retriever, query, context)

      # Check if retriever has a retrieve/2 function
      function_exported?(retriever, :retrieve, 2) ->
        retriever.retrieve(retriever, query)

      # Check if retriever module has a retrieve/2 function (module API)
      function_exported?(retriever, :retrieve, 2) ->
        retriever.retrieve(query, context)

      # Otherwise, return error
      true ->
        {:error, :retriever_not_available}
    end
  end

  defp maybe_apply_correction(context, config) do
    # Check retrieval quality
    quality = Map.get(context, :quality, 1.0)
    threshold = Map.get(config, :min_quality_threshold, 0.5)

    if quality < threshold do
      # Apply correction
      corrected_context = Map.put(context, :corrected, true)
      {corrected_context, true}
    else
      {context, false}
    end
  end
end
