defmodule Jido.HTN.Domain do
  @moduledoc """
  Represents the domain for Hierarchical Task Network (HTN) planning.

  This module provides functions to create and manipulate an HTN domain,
  including adding tasks, workflows, and callbacks, as well as validating
  the domain structure.
  """

  alias __MODULE__
  alias Jido.HTN.CompoundTask
  alias Jido.HTN.PrimitiveTask

  @type t :: %__MODULE__{
          name: String.t(),
          tasks: %{String.t() => CompoundTask.t() | PrimitiveTask.t()},
          allowed_workflows: %{optional(String.t()) => module()},
          callbacks: %{String.t() => (map() -> boolean()) | (map() -> map())},
          root_tasks: MapSet.t(String.t())
        }

  defstruct [:name, tasks: %{}, allowed_workflows: %{}, callbacks: %{}, root_tasks: MapSet.new()]

  # Builder Methods
  defdelegate new(name), to: Domain.BuilderHelpers
  defdelegate compound(builder, name, opts \\ []), to: Domain.BuilderHelpers
  defdelegate primitive(builder, name, task, opts \\ []), to: Domain.BuilderHelpers
  defdelegate callback(builder, name, callback), to: Domain.BuilderHelpers
  defdelegate allow(builder, name, module), to: Domain.BuilderHelpers
  defdelegate replace(builder, name, new_task), to: Domain.BuilderHelpers
  defdelegate root(builder, name), to: Domain.BuilderHelpers
  defdelegate build(builder), to: Domain.BuilderHelpers
  defdelegate build!(builder), to: Domain.BuilderHelpers

  # Read Methods
  defdelegate get_primitive(domain, name), to: Domain.ReadHelpers
  defdelegate get_compound(domain, name), to: Domain.ReadHelpers
  defdelegate tasks_to_map(domain), to: Domain.ReadHelpers
  defdelegate list_tasks(domain), to: Domain.ReadHelpers
  defdelegate list_allowed_workflows(domain), to: Domain.ReadHelpers
  defdelegate list_callbacks(domain), to: Domain.ReadHelpers

  # Validation Methods
  defdelegate validate(domain), to: Domain.ValidationHelpers
end
