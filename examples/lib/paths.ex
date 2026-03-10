defmodule Jido.AI.Examples.Paths do
  @moduledoc false

  @examples_root Path.expand("..", __DIR__)
  @repo_root Path.expand("..", @examples_root)

  def examples_root, do: @examples_root
  def repo_root, do: @repo_root

  def repo_path(relative_path) when is_binary(relative_path) do
    Path.join(@repo_root, relative_path)
  end

  def examples_relative_repo_path(relative_path) when is_binary(relative_path) do
    repo_path(relative_path)
    |> Path.relative_to(@examples_root)
  end
end
