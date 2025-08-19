# GitHub VFS Demo
# Demonstrates mounting a GitHub repository as a virtual filesystem with revision support

alias Kodo.VFS

# Start an instance
{:ok, _pid} = Kodo.start(:github_demo)

IO.puts("=== GitHub VFS Demo ===")

# Example 1: Mount a public GitHub repository (read-only)
# Note: This would work with a real GitHub repository
IO.puts("\n1. Example GitHub repo mount configuration:")

github_config = %{
  owner: "octocat",
  repo: "Hello-World",
  ref: "master",
  # For public repos, no auth needed
  # For private repos, you would add:
  # auth: %{access_token: System.get_env("GITHUB_TOKEN")}
}

IO.puts("   GitHub config: #{inspect(github_config)}")

# Mount configuration (demo - would work with real GitHub token)
IO.puts("\n2. Mount command example:")
IO.puts("   Kodo.mount(:github_demo, \"/github\", Depot.Adapter.GitHub, github_config)")

# Example 2: Show revision operations that would be available
IO.puts("\n3. Revision operations available after mounting:")
IO.puts("   # List recent commits")
IO.puts("   Kodo.revisions(:github_demo, \".\")")
IO.puts("")
IO.puts("   # Read a file at a specific commit")
IO.puts("   Kodo.read_revision(:github_demo, \"README\", \"<commit_sha>\")")
IO.puts("")
IO.puts("   # Read current version of a file")
IO.puts("   Kodo.read(:github_demo, \"/github/README\")")

# Example 3: Local Git repository demo (this actually works)
IO.puts("\n4. Local Git repository example:")

# Create a temporary git repo for demonstration
git_path = System.tmp_dir!() |> Path.join("demo_git_#{:rand.uniform(10000)}")
File.mkdir_p!(git_path)

# Initialize git repo
System.cmd("git", ["init"], cd: git_path)
System.cmd("git", ["config", "user.name", "Demo User"], cd: git_path)
System.cmd("git", ["config", "user.email", "demo@example.com"], cd: git_path)

# Create initial content
test_file = Path.join(git_path, "demo.txt")
File.write!(test_file, "Initial content v1")
System.cmd("git", ["add", "."], cd: git_path)
System.cmd("git", ["commit", "-m", "Initial commit"], cd: git_path)

# Add more content
File.write!(test_file, "Updated content v2")
System.cmd("git", ["add", "."], cd: git_path)
System.cmd("git", ["commit", "-m", "Update content"], cd: git_path)

# Mount the git repo
IO.puts("   Mounting local git repo...")
result = Kodo.mount(:github_demo, "/git", Depot.Adapter.Git, path: git_path, mode: :auto)
IO.puts("   Mount result: #{inspect(result)}")

if result == :ok do
  # Test reading current content
  case Kodo.read(:github_demo, "/git/demo.txt") do
    {:ok, content} -> 
      IO.puts("   Current content: #{inspect(content)}")
    error -> 
      IO.puts("   Error reading: #{inspect(error)}")
  end

  # Test listing revisions
  case Kodo.revisions(:github_demo, "/git/demo.txt") do
    {:ok, revisions} -> 
      IO.puts("   Found #{length(revisions)} revisions")
      for revision <- Enum.take(revisions, 2) do
        IO.puts("     - #{revision.sha}: #{revision.message}")
      end
    error -> 
      IO.puts("   Error getting revisions: #{inspect(error)}")
  end

  # Test reading old revision
  case Kodo.revisions(:github_demo, "/git/demo.txt") do
    {:ok, [_latest, older | _]} ->
      case Kodo.read_revision(:github_demo, "/git/demo.txt", older.sha) do
        {:ok, old_content} -> 
          IO.puts("   Content at #{String.slice(older.sha, 0, 7)}: #{inspect(old_content)}")
        error -> 
          IO.puts("   Error reading old revision: #{inspect(error)}")
      end
    _ -> 
      IO.puts("   Not enough revisions to compare")
  end
end

# Show mounted filesystems
IO.puts("\n5. Current mounts:")
{root_fs, mounts} = Kodo.mounts(:github_demo)
IO.puts("   Root filesystem: #{inspect(root_fs)}")
for {mount_point, filesystem} <- mounts do
  IO.puts("   #{mount_point}: #{inspect(filesystem)}")
end

# Cleanup
on_exit = fn ->
  File.rm_rf!(git_path)
  Kodo.stop(:github_demo)
end

IO.puts("\n=== Demo complete ===")
IO.puts("Note: For actual GitHub integration, you would:")
IO.puts("1. Set GITHUB_TOKEN environment variable with your personal access token")
IO.puts("2. Use Depot.Adapter.GitHub with proper authentication")
IO.puts("3. All revision operations (commit, revisions, read_revision, rollback) would then work")

# Run cleanup
on_exit.()
