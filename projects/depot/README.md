# Depot

![Elixir CI](https://github.com/LostKobrakai/depot/workflows/Elixir%20CI/badge.svg)  
[Hex Package](https://hex.pm/depot) | 
[Online Documentation](https://hexdocs.pm/depot).

<!-- MDOC !-->

Depot is a filesystem abstraction for elixir providing a unified interface over many implementations. It allows you to swap out filesystems on the fly without needing to rewrite all of your application code in the process. It can eliminate vendor-lock in, reduce technical debt, and improve the testability of your code.

This library is based on the ideas of [flysystem](http://flysystem.thephpleague.com/), which is a PHP library providing similar functionality.

## Examples

```elixir
defmodule LocalFileSystem do
  use Depot.Filesystem,
    adapter: Depot.Adapter.Local,
    prefix: prefix
end

LocalFileSystem.write("test.txt", "Hello World")
{:ok, "Hello World"} = LocalFileSystem.read("test.txt")
```

### Git Adapter with Versioning

The Git adapter provides version-controlled filesystem operations:

```elixir
# Configure Git filesystem with manual commits
{_module, filesystem} = Depot.Adapter.Git.configure(
  path: "/path/to/repo",
  mode: :manual,
  author: [name: "Bot", email: "bot@example.com"]
)

# Write files and commit manually
Depot.write(filesystem, "document.txt", "Version 1")
Depot.commit(filesystem, "Add initial document")

# View revision history
{:ok, revisions} = Depot.revisions(filesystem, "document.txt")

# Read historical versions
{:ok, old_content} = Depot.read_revision(filesystem, "document.txt", revision_sha)

# Auto-commit mode
{_module, auto_fs} = Depot.Adapter.Git.configure(path: "/repo", mode: :auto)
Depot.write(auto_fs, "file.txt", "content")  # Automatically committed
```

### GitHub Adapter

The GitHub adapter allows you to interact with GitHub repositories as a virtual filesystem:

```elixir
# Configure GitHub filesystem for public repo (read-only)
{_module, github_fs} = Depot.Adapter.GitHub.configure(
  owner: "octocat",
  repo: "Hello-World",
  ref: "main"
)

# Read files from GitHub
{:ok, content} = Depot.read(github_fs, "README.md")
{:ok, files} = Depot.list_contents(github_fs, "")

# Configure with authentication for write operations
{_module, auth_fs} = Depot.Adapter.GitHub.configure(
  owner: "your-username",
  repo: "your-repo",
  ref: "main",
  auth: %{access_token: "your_github_token"},
  commit_info: %{
    message: "Update via Depot",
    committer: %{name: "Your Name", email: "your@email.com"},
    author: %{name: "Your Name", email: "your@email.com"}
  }
)

# Write files (creates commits)
Depot.write(auth_fs, "new_file.txt", "Hello GitHub!", 
            message: "Add new file via Depot")

# Copy and move files
Depot.copy(auth_fs, "source.txt", "dest.txt", 
           message: "Copy file via Depot")
Depot.move(auth_fs, "old_name.txt", "new_name.txt", 
           message: "Rename file via Depot")

# Check file existence
{:ok, :exists} = Depot.file_exists(auth_fs, "README.md")
{:ok, :missing} = Depot.file_exists(auth_fs, "nonexistent.txt")
```

## Visibility

Depot does by default only deal with a limited, but portable, set of visibility permissions:

- `:public`
- `:private`

For more details and how to apply custom visibility permissions take a look at `Depot.Visibility`

## Options

  The following write options apply to all adapters:

  * `:visibility` - Set the visibility for files written
  * `:directory_visibility` - Set the visibility for directories written (if applicable)

<!-- MDOC !-->

## Installation

The package can be installed by adding `depot` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:depot, "~> 0.1.0"}
  ]
end
```
