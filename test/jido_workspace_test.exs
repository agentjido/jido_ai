defmodule JidoWorkspaceTest do
  use ExUnit.Case
  doctest JidoWorkspace

  test "loads workspace config" do
    projects = JidoWorkspace.config()
    assert is_list(projects)
    assert length(projects) > 0
    
    jido_project = Enum.find(projects, &(&1.name == "jido"))
    assert jido_project != nil
    assert jido_project.upstream_url == "https://github.com/agentjido/jido"
  end

  test "workspace status returns ok" do
    assert JidoWorkspace.status() == :ok
  end
end
