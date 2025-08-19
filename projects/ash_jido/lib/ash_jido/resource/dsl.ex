defmodule AshJido.Resource.Dsl do
  @moduledoc """
  DSL section definition for the jido section.
  """

  def jido_section do
    %Spark.Dsl.Section{
      name: :jido,
      describe: """
      Configure which Ash actions should be exposed as Jido actions.
      """,
      entities: [
        %Spark.Dsl.Entity{
          name: :action,
          describe: """
          Expose an Ash action as a Jido action.

          ## Usage Examples

          Simple syntax (uses all defaults):
          ```elixir
          jido do
            action :create
            action :read
            action :update
          end
          ```

          With custom name and description:
          ```elixir
          jido do
            action :create, name: "create_user", description: "Create a new user account"
          end
          ```

          With tags for AI discovery:
          ```elixir
          jido do
            action :read, tags: ["search", "user-management", "public"]
          end
          ```

          Expose all actions with defaults:
          ```elixir
          jido do
            all_actions
          end
          ```
          """,
          target: AshJido.Resource.JidoAction,
          args: [:action],
          schema: [
            action: [
              type: :atom,
              required: true,
              doc: "The name of the Ash action to expose"
            ],
            name: [
              type: :string,
              doc: "Custom name for the Jido action. Defaults to smart naming: 'resource_action'"
            ],
            module_name: [
              type: :atom,
              doc: "Custom module name. Defaults to: 'Resource.Jido.ActionName'"
            ],
            description: [
              type: :string,
              doc:
                "Description for the Jido action. Inherits from Ash action description if available"
            ],
            tags: [
              type: {:list, :string},
              default: [],
              doc:
                "Tags for better categorization and AI discovery. Auto-generates smart defaults"
            ],
            output_map?: [
              type: :boolean,
              default: true,
              doc: "Convert output structs to maps (recommended for AI tools)"
            ],
            pagination?: [
              type: :boolean,
              default: true,
              doc: "Include pagination parameters for read actions"
            ]
          ]
        },
        %Spark.Dsl.Entity{
          name: :all_actions,
          describe: """
          Expose all Ash actions as Jido actions with smart defaults.

          This creates Jido actions for all create, read, update, destroy, and custom actions
          defined on the resource, using intelligent naming and categorization.

          ## Usage

          ```elixir
          jido do
            all_actions
            # Optionally exclude specific actions
            all_actions except: [:internal_action, :admin_only]
          end
          ```
          """,
          target: AshJido.Resource.AllActions,
          args: [],
          schema: [
            except: [
              type: {:list, :atom},
              default: [],
              doc: "List of action names to exclude from auto-generation"
            ],
            only: [
              type: {:list, :atom},
              doc: "If specified, only generate actions for these action names"
            ],
            tags: [
              type: {:list, :string},
              default: [],
              doc: "Additional tags to add to all generated actions"
            ]
          ]
        }
      ]
    }
  end
end
