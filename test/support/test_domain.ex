defmodule AshJido.Test.Domain do
  @moduledoc """
  Test domain for integration tests.
  """

  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource(AshJido.Test.User)
    resource(AshJido.Test.Post)
    resource(AshJido.Test.CustomModules)
  end

  # Make this domain accessible for testing
  def __using__(_opts) do
    quote do
      alias AshJido.Test.Domain
    end
  end
end
