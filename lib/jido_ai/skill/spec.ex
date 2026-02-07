defmodule Jido.AI.Skill.Spec do
  @moduledoc """
  Specification struct for skills, supporting both compile-time modules and runtime-loaded SKILL.md files.

  Follows the agentskills.io spec with Jido-specific extensions.
  """

  @type source :: {:module, module()} | {:file, String.t()}
  @type body_ref :: {:file, String.t()} | {:inline, String.t()} | nil

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          license: String.t() | nil,
          compatibility: String.t() | nil,
          metadata: map() | nil,
          allowed_tools: [String.t()],
          source: source() | nil,
          body_ref: body_ref(),
          actions: [module()],
          plugins: [module()],
          vsn: String.t() | nil,
          tags: [String.t()]
        }

  defstruct [
    :name,
    :description,
    :license,
    :compatibility,
    :metadata,
    allowed_tools: [],
    source: nil,
    body_ref: nil,
    actions: [],
    plugins: [],
    vsn: nil,
    tags: []
  ]
end
