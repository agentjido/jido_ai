defmodule Depot.Visibility.PortableUnixVisibilityConverter do
  @moduledoc """
  `Depot.Visibility.UnixVisibilityConverter` supporting `Depot.Visibility.portable()`.

  This is a good default visibility converter for adapters using unix based permissions.
  """
  alias Depot.Visibility.UnixVisibilityConverter

  defmodule Config do
    @moduledoc false

    @type t :: %__MODULE__{
            file_public: UnixVisibilityConverter.permission(),
            file_private: UnixVisibilityConverter.permission(),
            directory_public: UnixVisibilityConverter.permission(),
            directory_private: UnixVisibilityConverter.permission()
          }

    defstruct file_public: 0o644,
              file_private: 0o600,
              directory_public: 0o755,
              directory_private: 0o700
  end

  @behaviour UnixVisibilityConverter

  @impl UnixVisibilityConverter
  def config(config) do
    struct!(%Config{}, config)
  end

  @impl UnixVisibilityConverter
  def for_file(%Config{} = config, visibility) do
    with {:ok, visibility} <- Depot.Visibility.guard_portable(visibility) do
      case visibility do
        :public -> config.file_public
        :private -> config.file_private
      end
    end
  end

  @impl UnixVisibilityConverter
  def for_directory(%Config{} = config, visibility) do
    with {:ok, visibility} <- Depot.Visibility.guard_portable(visibility) do
      case visibility do
        :public -> config.directory_public
        :private -> config.directory_private
      end
    end
  end

  @impl UnixVisibilityConverter
  def from_file(%Config{} = config, permission) do
    cond do
      permission === config.file_public -> :public
      permission === config.file_private -> :private
      true -> :public
    end
  end

  @impl UnixVisibilityConverter
  def from_directory(%Config{} = config, permission) do
    cond do
      permission === config.directory_public -> :public
      permission === config.directory_private -> :private
      true -> :public
    end
  end
end
