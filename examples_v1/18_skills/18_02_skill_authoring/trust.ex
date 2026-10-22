defmodule JidoAI.Examples.SkillAuthoring.Trust do
  def allow(path, suffix), do: String.ends_with?(path, suffix)
end
