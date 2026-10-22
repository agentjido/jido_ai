defmodule Jido.AI.Plugin.DSL.Tools do
  @moduledoc false
  defstruct [:__spark_metadata__, entries: []]
end

defmodule Jido.AI.Plugin.DSL.ActionTool do
  @moduledoc false
  defstruct [:target, :as, :description, :__spark_metadata__, timeout: 5_000]
end

defmodule Jido.AI.Plugin.DSL.FlowTool do
  @moduledoc false
  defstruct [:target, :as, :description, :__spark_metadata__, timeout: 5_000]
end

defmodule Jido.AI.Plugin.DSL.Controls do
  @moduledoc false

  defstruct [
    :__spark_metadata__,
    timeout: 60_000,
    max_iterations: 8,
    max_model_calls: 12,
    max_tool_calls: 16,
    inputs: [],
    outputs: []
  ]
end

defmodule Jido.AI.Plugin.DSL.InputControl do
  @moduledoc false
  defstruct [:action, :__spark_metadata__]
end

defmodule Jido.AI.Plugin.DSL.OutputControl do
  @moduledoc false
  defstruct [:action, :__spark_metadata__]
end
