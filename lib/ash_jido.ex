defmodule AshJido do
  @moduledoc """
  AshJido bridges Ash Framework resources with Jido actions.

  This library provides an Ash Framework extension that automatically generates Jido.Action
  modules from Ash Resources, enabling every Ash action to become a tool
  in an agent's toolbox while maintaining type safety and Ash policies.

  ## Usage

  Add the extension to your Ash resource:

      defmodule MyApp.Accounts.User do
        use Ash.Resource,
          extensions: [AshJido]

        actions do
          create :register
          read :by_id, primary?: true
        end

        jido do
          action :register
          action :by_id, name: "get_user", module_name: MyApp.UserFinder
        end
      end

  This will generate corresponding Jido.Action modules that can be used
  in agents and workflows.

  ## DSL

      jido do
        action :create_action              # Auto-generate with defaults
        action :read_action, name: "custom_name"  # Custom action name
        action :special_action, module_name: MyApp.SpecialModule  # Custom module name
      end

  ## DSL Options

  The `action` keyword supports both simple and advanced usage:

  - Simple: `action :create` - Exposes the action with default settings
  - Advanced: `action :create, options` - Exposes the action with custom configuration

  ### Action Options

  - `name` - Custom name for the Jido action (defaults to "resource_action")
  - `module_name` - Custom module name for the generated Jido.Action (defaults to "Resource.Jido.ActionName")
  - `description` - Description for the action (defaults to Ash action description)
  - `output_map?` - Convert output structs to maps (default: true)
  - `pagination?` - Include pagination params for read actions (default: true)
  """

  @sections [AshJido.Resource.Dsl.jido_section()]

  use Spark.Dsl.Extension,
    transformers: [AshJido.Resource.Transformers.GenerateJidoActions],
    sections: @sections

  @doc """
  Returns the version of AshJido.
  """
  def version, do: Mix.Project.config()[:version]

  @doc false
  def explain(dsl_state, opts) do
    Spark.Dsl.Extension.explain(dsl_state, __MODULE__, nil, opts)
  end
end
