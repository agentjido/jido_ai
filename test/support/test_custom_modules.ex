defmodule AshJido.Test.CustomModules do
  @moduledoc """
  Test resource for demonstrating custom module name overrides.

  This resource shows different ways to customize module names:
  - Default naming: action :create -> AshJido.Test.CustomModules.Jido.Create
  - Full module path: module_name: AshJido.Test.Publishers.ItemPublisher
  - Simple name: module_name: StatusFinder  
  - Nested namespace: module_name: AshJido.Test.Readers.AllItemsReader
  """

  use Ash.Resource,
    domain: nil,
    extensions: [AshJido],
    data_layer: Ash.DataLayer.Ets

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false)
    attribute(:status, :string, default: "draft")
    timestamps()
  end

  actions do
    defaults([:read])

    create :create do
      accept([:title, :status])
    end

    create :publish do
      description("Publish an item")
      argument(:title, :string, allow_nil?: false)
      argument(:priority, :integer, default: 1)

      change(set_attribute(:title, arg(:title)))
      change(set_attribute(:status, "published"))
    end

    read :by_status do
      description("Find items by status")
      argument(:status, :string, allow_nil?: false)

      filter(expr(status == ^arg(:status)))
    end
  end

  jido do
    # Default module name: AshJido.Test.CustomModules.Jido.Create
    action(:create)

    # Custom module name using full path
    action(:publish,
      name: "publish_item",
      module_name: AshJido.Test.Publishers.ItemPublisher
    )

    # Custom module name using atom shorthand
    action(:by_status,
      name: "find_by_status",
      module_name: StatusFinder
    )

    # Custom module name in a different namespace
    action(:read,
      name: "list_all",
      module_name: AshJido.Test.Readers.AllItemsReader
    )
  end
end
