defmodule Sparq.Evaluator.Script do
  @moduledoc """
  Evaluator for script-specific constructs like character, scene, and beat blocks.
  """

  @doc """
  Evaluates a character definition.
  Creates a new module in the context with the character's name.
  """
  def evaluate_character({:character, _meta, [name, _body]}, context) do
    # Create a new module for the character
    module_object = %{
      type: :module,
      name: name,
      functions: %{},
      state: %{}
    }

    # Store module in context
    context = %{context | modules: Map.put(context.modules, name, module_object)}
    {nil, context}
  end

  @doc """
  Evaluates a scene definition.
  Creates a new module in the context with the scene's name and beats.
  """
  def evaluate_scene({:scene, _meta, [name, body]}, context) do
    # Extract beats from body tokens
    beats =
      body
      |> Enum.filter(&match?({:beat, _, _}, &1))
      |> Enum.map(&extract_beat/1)
      |> Enum.into(%{})

    # Create a new module for the scene
    module_object = %{
      type: :module,
      name: name,
      functions: %{},
      state: %{
        beats: beats
      }
    }

    # Store module in context
    context = %{context | modules: Map.put(context.modules, name, module_object)}
    {nil, context}
  end

  @doc """
  Evaluates a beat definition.
  Returns a tuple of {beat_name, beat_commands}.
  """
  def evaluate_beat({:beat, _meta, [name, body]}, _context) do
    # Extract commands from body tokens
    commands =
      body
      |> Enum.filter(&match?({:say, _, _}, &1))
      |> Enum.map(&extract_command/1)

    {name, commands}
  end

  @doc """
  Evaluates a say command.
  Currently just returns the command tuple, but will eventually call JITO.
  """
  def evaluate_say({:say, _meta, [character, text]}, context) do
    # TODO: Call JITO handler
    {{:say, character, text}, context}
  end

  # Private helpers

  defp extract_beat({:beat, _, [name, body]}) do
    commands =
      body
      |> Enum.filter(&match?({:say, _, _}, &1))
      |> Enum.map(&extract_command/1)

    {name, commands}
  end

  defp extract_command({:say, _, [character, text]}) do
    {:say, character, text}
  end
end
