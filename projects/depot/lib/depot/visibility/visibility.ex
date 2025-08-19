defmodule Depot.Visibility do
  @type t :: portable | custom
  @type portable :: :public | :private
  @type custom :: term

  @spec portable?(any) :: boolean
  def portable?(:public), do: true
  def portable?(:private), do: true
  def portable?(_), do: false

  @spec guard_portable(any) :: {:ok, Depot.Visibility.portable()} | :error
  def guard_portable(visibility) do
    if portable?(visibility) do
      {:ok, visibility}
    else
      :error
    end
  end
end
