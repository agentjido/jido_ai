defmodule AshJido.Test.Post do
  @moduledoc """
  Test Post resource for integration tests.
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
    attribute(:content, :string)
    attribute(:published, :boolean, default: false)
    timestamps()
  end

  actions do
    defaults([:read, :update, :destroy])

    create :create do
      accept([:title, :content, :published])
    end

    create :publish do
      description("Create and publish a post")
      argument(:title, :string, allow_nil?: false)
      argument(:content, :string)

      change(set_attribute(:title, arg(:title)))
      change(set_attribute(:content, arg(:content)))
      change(set_attribute(:published, true))
    end
  end

  jido do
    action(:create)
    action(:read)
    action(:publish, name: "publish_post")
  end
end
