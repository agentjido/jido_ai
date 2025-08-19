defmodule Jido.Character.Macros do
  @moduledoc """
  Helpful macros for common character operations.
  """

  @doc """
  Defines standard CRUD functions for an embedded schema.
  """
  defmacro def_crud(schema_name) do
    quote do
      def unquote(:"update_#{schema_name}")(%Jido.Character{} = character, attrs) do
        Jido.Character.update(character, %{unquote(schema_name) => attrs})
      end

      def unquote(:"get_#{schema_name}")(%Jido.Character{} = character) do
        Map.get(character, unquote(schema_name))
      end
    end
  end

  @doc """
  Defines a field accessor with optional default value.
  """
  defmacro def_field_accessor(field_name, default \\ nil) do
    quote do
      def unquote(:"get_#{field_name}")(%Jido.Character{} = character) do
        Map.get(character, unquote(field_name), unquote(default))
      end
    end
  end
end
