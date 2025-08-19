defmodule AshJido.Resource.Transformers.GenerateJidoActions do
  @moduledoc """
  Transformer that generates Jido.Action modules from Ash actions at compile time.

  This transformer runs after the Ash DSL is finalized and creates a Jido.Action
  module for each configured jido_action.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  alias AshJido.Generator

  @doc false
  def transform(dsl_state) do
    resource = Transformer.get_persisted(dsl_state, :module)
    jido_entities = Transformer.get_entities(dsl_state, [:jido])

    case jido_entities do
      [] ->
        {:ok, dsl_state}

      entities when is_list(entities) ->
        try do
          # Expand all_actions entities into individual jido_action entities
          expanded_actions = expand_jido_entities(resource, entities, dsl_state)
          generated_modules = generate_jido_actions(resource, expanded_actions, dsl_state)

          dsl_state =
            dsl_state
            |> Transformer.persist(:generated_jido_modules, generated_modules)

          {:ok, dsl_state}
        rescue
          error ->
            {:error, error}
        end
    end
  end

  @doc false
  def before?(_), do: false

  @doc false
  def after?(Ash.Resource.Transformers.ValidateRelationshipAttributes), do: true
  def after?(_), do: false

  defp expand_jido_entities(resource, entities, dsl_state) do
    Enum.flat_map(entities, fn entity ->
      case entity do
        %AshJido.Resource.AllActions{} = all_actions ->
          expand_all_actions(resource, all_actions, dsl_state)

        %AshJido.Resource.JidoAction{} = jido_action ->
          [jido_action]
      end
    end)
  end

  defp expand_all_actions(_resource, all_actions, dsl_state) do
    # Get all actions from the resource
    all_ash_actions = get_all_ash_actions(dsl_state)

    # Filter based on only/except options
    filtered_actions = filter_actions(all_ash_actions, all_actions)

    # Convert to JidoAction structs with smart defaults
    Enum.map(filtered_actions, fn ash_action ->
      %AshJido.Resource.JidoAction{
        action: ash_action.name,
        # Will use smart defaults
        name: nil,
        # Will use smart defaults
        module_name: nil,
        # Will inherit from ash action
        description: nil,
        # Additional tags from all_actions
        tags: all_actions.tags || [],
        output_map?: true,
        pagination?: true
      }
    end)
  end

  defp get_all_ash_actions(dsl_state) do
    # Get all action types from the DSL state
    Transformer.get_entities(dsl_state, [:actions])
  end

  defp filter_actions(ash_actions, %{only: only, except: _except}) when not is_nil(only) do
    # If 'only' is specified, only include those actions
    Enum.filter(ash_actions, fn action -> action.name in only end)
  end

  defp filter_actions(ash_actions, %{except: except}) when is_list(except) do
    # Exclude specified actions
    Enum.reject(ash_actions, fn action -> action.name in except end)
  end

  defp filter_actions(ash_actions, _), do: ash_actions

  defp generate_jido_actions(resource, jido_actions, dsl_state) do
    Enum.map(jido_actions, fn jido_action ->
      Generator.generate_jido_action_module(resource, jido_action, dsl_state)
    end)
  end
end
