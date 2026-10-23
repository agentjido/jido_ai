defmodule Jido.AI.Plugin do
  @moduledoc """
  Adds AI configuration to a Jido Agent.

      defmodule MyApp.Assistant do
        use Jido.AI.Agent, name: "assistant"

        ai do
          model :fast
          instructions "Reply in one short sentence."
          reasoning MyApp.ReasoningFlow

          tools do
            action MyApp.Search, as: :search
            flow MyApp.Research, as: :research
          end

          controls do
            timeout 30_000
            max_model_calls 3
            max_tool_calls 4
            input MyApp.AuthorizeRequest

            output %{output: output},
              schema: Zoi.object(%{output: Zoi.string()}) do
              if output == "", do: {:error, :empty_answer}, else: {:ok, %{accepted: true}}
            end
          end
        end
      end

  Define the reasoning Flow inline when it belongs to only one Agent:

      ai do
        model :fast

        reasoning do
          step "model", action: Jido.AI.Actions.CallModel, params: input(:request)
          step "complete", action: Jido.AI.Actions.CompleteResponse, params: result("model")
          output result("complete")
        end
      end

  Tool declarations use Jido Actions and Flows. Each input or output control
  slot accepts one Jido Action. The Plugin only stores static configuration.
  It does not call a model or start a process.
  """

  alias Jido.AI.Plugin.DSL
  alias Jido.Agent.{Data, Error}
  alias Jido.Instruction
  alias Spark.Dsl.Extension, as: Extension

  @default_reasoning Jido.AI.Flow.ReAct

  @default_controls %{
    timeout: 60_000,
    max_iterations: 8,
    max_model_calls: 12,
    max_tool_calls: 16,
    input: nil,
    output: nil
  }

  @reasoning %Spark.Dsl.Entity{
    name: :__reasoning__,
    target: DSL.Reasoning,
    args: [:target],
    schema: [target: [type: :atom, required: true]]
  }

  @action_tool %Spark.Dsl.Entity{
    name: :action,
    target: DSL.ActionTool,
    args: [:target],
    schema: [
      target: [type: :atom, required: true],
      as: [type: :atom],
      description: [type: :string],
      timeout: [type: :pos_integer, default: 5_000]
    ]
  }

  @flow_tool %Spark.Dsl.Entity{
    name: :flow,
    target: DSL.FlowTool,
    args: [:target],
    schema: @action_tool.schema
  }

  @tools %Spark.Dsl.Entity{
    name: :tools,
    target: DSL.Tools,
    entities: [entries: [@action_tool, @flow_tool]]
  }

  @input_control %Spark.Dsl.Entity{
    name: :input,
    target: DSL.InputControl,
    args: [:action],
    schema: [action: [type: :atom, required: true]]
  }

  @output_control %Spark.Dsl.Entity{
    name: :output,
    target: DSL.OutputControl,
    args: [:action],
    schema: [action: [type: :atom, required: true]]
  }

  @controls %Spark.Dsl.Entity{
    name: :controls,
    target: DSL.Controls,
    schema: [
      timeout: [type: :pos_integer, default: @default_controls.timeout],
      max_iterations: [type: :pos_integer, default: @default_controls.max_iterations],
      max_model_calls: [type: :pos_integer, default: @default_controls.max_model_calls],
      max_tool_calls: [type: :pos_integer, default: @default_controls.max_tool_calls]
    ],
    entities: [input: [@input_control], output: [@output_control]],
    singleton_entity_keys: [:input, :output]
  }

  @section %Spark.Dsl.Section{
    name: :ai,
    schema: [
      model: [type: {:or, [:string, :atom]}, required: true],
      instructions: [type: :string, default: ""]
    ],
    entities: [@reasoning, @tools, @controls],
    singleton_entity_keys: [:__reasoning__, :tools, :controls]
  }

  use Jido.Plugin, id: "jido.ai", sections: [@section]

  @impl Jido.Plugin
  def state_spec(_opts), do: :none

  @impl Jido.Plugin
  def prepare(_preparation, opts) do
    case Map.new(opts) do
      config when map_size(config) > 0 -> {:ok, config}
      _config -> {:error, :missing_ai_config}
    end
  end

  @impl Jido.Agent.Extension
  def authoring_imports,
    do: [Jido.AI.Plugin.DSL.ControlMacros, Jido.AI.Plugin.DSL.ReasoningMacros]

  @impl Jido.Agent.Extension
  defdelegate encode_authoring_data(data, registry),
    to: Jido.AI.Plugin.Authoring,
    as: :encode

  @impl Jido.Agent.Extension
  defdelegate decode_authoring_data(data, registry),
    to: Jido.AI.Plugin.Authoring,
    as: :decode

  @impl Jido.Agent.Extension
  def lower(dsl, config) do
    model = Extension.get_opt(dsl, [:ai], :model)
    instructions = Extension.get_opt(dsl, [:ai], :instructions, "")
    entities = Extension.get_entities(dsl, [:ai])
    reasoning = Enum.find(entities, &is_struct(&1, DSL.Reasoning))
    tools = Enum.find(entities, &is_struct(&1, DSL.Tools))
    controls = Enum.find(entities, &is_struct(&1, DSL.Controls))
    dsl_used? = model != nil or entities != []

    cond do
      dsl_used? and config != %{} ->
        {:error, :use_ai_block_or_config}

      config != %{} ->
        {:ok, config}

      model != nil ->
        ai_config = %{
          model: model,
          instructions: instructions,
          reasoning: lower_reasoning(reasoning),
          tools: lower_tools(tools),
          controls: lower_controls(controls)
        }

        {:ok, ai_config}

      true ->
        {:error, :missing_ai_config}
    end
  end

  @impl Jido.Agent.Extension
  def normalize(data) do
    with {:ok, ai_config} <-
           Data.fields(
             data,
             [:model, :instructions, :reasoning, :tools, :controls],
             %{
               instructions: "",
               reasoning: @default_reasoning,
               tools: [],
               controls: @default_controls
             }
           ),
         :ok <- validate_model(ai_config.model),
         :ok <- validate_instructions(ai_config.instructions),
         :ok <- Error.at(validate_executable(ai_config.reasoning, :flow), :reasoning),
         {:ok, tools} <- Error.at(validate_tools(ai_config.tools), :tools),
         {:ok, controls} <- Error.at(validate_controls(ai_config.controls), :controls) do
      normalized = %{
        model: ai_config.model,
        instructions: ai_config.instructions,
        reasoning: ai_config.reasoning,
        tools: tools,
        controls: controls
      }

      {:ok, normalized}
    end
  end

  @doc "Returns the Agent's static AI configuration."
  @spec config(module() | Jido.Agent.t()) :: map() | nil
  def config(agent) when is_atom(agent), do: config(agent.definition())

  def config(%Jido.Agent{extensions: extensions}) do
    case Enum.find(extensions, &(&1.provider == __MODULE__)) do
      %{data: config} -> config
      nil -> nil
    end
  end

  @doc false
  def default_controls, do: @default_controls

  @doc false
  def default_reasoning, do: @default_reasoning

  defp lower_reasoning(nil), do: @default_reasoning
  defp lower_reasoning(%DSL.Reasoning{target: target}), do: target

  defp lower_tools(nil), do: []

  defp lower_tools(%DSL.Tools{entries: entries}) do
    Enum.map(entries, fn
      %DSL.ActionTool{} = tool -> lower_tool(tool, :action)
      %DSL.FlowTool{} = tool -> lower_tool(tool, :flow)
    end)
  end

  defp lower_tool(tool, kind) do
    %{
      kind: kind,
      target: tool.target,
      as: tool.as,
      description: tool.description,
      timeout: tool.timeout
    }
  end

  defp lower_controls(nil), do: @default_controls

  defp lower_controls(%DSL.Controls{} = controls) do
    %{
      timeout: controls.timeout,
      max_iterations: controls.max_iterations,
      max_model_calls: controls.max_model_calls,
      max_tool_calls: controls.max_tool_calls,
      input: control_action(controls.input),
      output: control_action(controls.output)
    }
  end

  defp validate_tools(tools) do
    with {:ok, tools} <- Data.list(tools, &validate_tool/1),
         :ok <- Data.unique(tools, & &1.name),
         do: {:ok, tools}
  end

  defp validate_tool(value) do
    with {:ok, value} <-
           Data.fields(value, [:kind, :target, :as, :name, :description, :timeout], %{
             as: nil,
             name: nil,
             description: nil,
             timeout: 5_000
           }),
         :ok <- validate_tool_kind(value.kind),
         :ok <- validate_executable(value.target, value.kind),
         :ok <- validate_tool_names(value.as, value.name),
         :ok <- validate_optional_description(value.description),
         :ok <- Data.positive(value.timeout) do
      {:ok,
       %{
         kind: value.kind,
         target: value.target,
         name: tool_name(value.target, value.as, value.name),
         description: value.description || value.target.description() || "",
         timeout: value.timeout
       }}
    end
  end

  defp validate_controls(value) do
    with {:ok, value} <-
           Data.fields(
             value,
             [:timeout, :max_iterations, :max_model_calls, :max_tool_calls, :input, :output],
             @default_controls
           ),
         :ok <- Data.positive(value.timeout),
         :ok <- Data.positive(value.max_iterations),
         :ok <- Data.positive(value.max_model_calls),
         :ok <- Data.positive(value.max_tool_calls),
         {:ok, input} <- Error.at(validate_control_action(value.input), :input),
         {:ok, output} <- Error.at(validate_control_action(value.output), :output) do
      {:ok, %{value | input: input, output: output}}
    end
  end

  defp validate_control_action(nil), do: {:ok, nil}

  defp validate_control_action(action) do
    with :ok <- validate_executable(action, :action), do: {:ok, action}
  end

  defp control_action(nil), do: nil
  defp control_action(control), do: control.action

  defp validate_executable(target, kind)
       when is_atom(target) and target not in [nil, true, false] do
    with {:ok, executable} <- Instruction.resolve(target),
         :ok <- Instruction.validate(executable),
         true <- executable.kind == kind do
      :ok
    else
      {:error, reason} -> invalid_executable(target, kind, reason)
      false -> invalid_executable(target, kind, :target_kind_mismatch)
    end
  end

  defp validate_executable(target, kind) do
    invalid_executable(target, kind, :invalid_target)
  end

  defp invalid_executable(target, kind, reason) do
    Error.fail(:invalid_executable, [], "Expected a Jido #{kind} module", %{
      target: target,
      kind: kind,
      reason: reason
    })
  end

  defp validate_tool_kind(kind) when kind in [:action, :flow], do: :ok

  defp validate_tool_kind(kind),
    do: Error.fail(:invalid_tool_kind, [], "Expected :action or :flow", %{kind: kind})

  defp validate_tool_names(nil, nil), do: :ok
  defp validate_tool_names(value, nil), do: Data.name(value)
  defp validate_tool_names(nil, value), do: Data.nonempty(value)

  defp validate_tool_names(as, name) do
    Error.fail(:ambiguous_tool_name, [], "Use either :as or :name, not both", %{
      as: as,
      name: name
    })
  end

  defp validate_optional_description(nil), do: :ok
  defp validate_optional_description(value), do: Data.nonempty(value)

  defp validate_instructions(""), do: :ok
  defp validate_instructions(value), do: Data.nonempty(value)

  defp validate_model(value) when is_atom(value) and value not in [nil, true, false], do: :ok
  defp validate_model(value), do: Data.nonempty(value)

  defp tool_name(target, nil, nil), do: target.name()
  defp tool_name(_target, name, nil), do: Atom.to_string(name)
  defp tool_name(_target, nil, name), do: name
end
