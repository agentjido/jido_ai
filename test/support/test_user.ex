defmodule AshJido.Test.User do
  @moduledoc """
  Test User resource for integration tests.
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
    attribute(:name, :string, allow_nil?: false)
    attribute(:email, :string, allow_nil?: false)
    attribute(:age, :integer)
    attribute(:active, :boolean, default: true)
    timestamps()
  end

  actions do
    defaults([:read, :destroy])

    create :register do
      description("Register a new user")
      argument(:name, :string, allow_nil?: false)
      argument(:email, :string, allow_nil?: false)
      argument(:age, :integer)

      change(set_attribute(:name, arg(:name)))
      change(set_attribute(:email, arg(:email)))
      change(set_attribute(:age, arg(:age)))
    end

    read :by_email do
      description("Find user by email")
      argument(:email, :string, allow_nil?: false)

      filter(expr(email == ^arg(:email)))
    end

    update :update_age do
      description("Update user age")
      argument(:age, :integer, allow_nil?: false)

      change(set_attribute(:age, arg(:age)))
    end

    # Custom destroy action with additional validation
    destroy :archive do
      description("Archive a user instead of deleting")
      change(set_attribute(:active, false))
    end

    # Generic action example
    action :deactivate do
      description("Deactivate a user account")
      argument(:reason, :string)

      run(fn input, context ->
        # This would be a custom implementation
        {:ok, %{message: "User deactivated", reason: input.arguments.reason}}
      end)
    end
  end

  jido do
    action(:register)

    action(:by_email,
      name: "find_user_by_email",
      description: "Find a user by their email address"
    )

    action(:read)
    action(:update_age, name: "update_user_age", output_map?: true)
    action(:destroy, name: "delete_user")
    action(:archive, name: "archive_user")
    action(:deactivate, name: "deactivate_user")
  end
end
