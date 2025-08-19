# Simple VFS demo to verify mount/unmount functionality
IO.puts("=== VFS Mount/Unmount Demo ===")

# Start a demo instance
{:ok, _} = Kodo.start(:demo)

# Mount a filesystem
IO.puts("\n1. Mounting filesystem at /tmp...")
:ok = Kodo.mount(:demo, "/tmp", Depot.Adapter.InMemory, name: :TmpFS)

# List mounts
{_root, mounts} = Kodo.mounts(:demo)
IO.inspect(mounts, label: "2. Mounted filesystems")

# Write to different filesystems
IO.puts("\n3. Writing files...")
:ok = Kodo.write(:demo, "/root.txt", "Root filesystem content")
:ok = Kodo.write(:demo, "/tmp/temp.txt", "Temporary filesystem content")

# Read from different filesystems
{:ok, root_content} = Kodo.read(:demo, "/root.txt")
{:ok, temp_content} = Kodo.read(:demo, "/tmp/temp.txt")
IO.puts("   Root file: #{root_content}")
IO.puts("   Temp file: #{temp_content}")

# List files in each filesystem
{:ok, root_files} = Kodo.ls(:demo, "/")
{:ok, temp_files} = Kodo.ls(:demo, "/tmp")
IO.puts("\n4. Root files: #{Enum.map(root_files, & &1.name) |> Enum.join(", ")}")
IO.puts("   Temp files: #{Enum.map(temp_files, & &1.name) |> Enum.join(", ")}")

# Check file existence
exists_root = Kodo.exists?(:demo, "/root.txt")
exists_temp = Kodo.exists?(:demo, "/tmp/temp.txt")
IO.puts("\n5. File existence checks:")
IO.puts("   /root.txt exists: #{exists_root}")
IO.puts("   /tmp/temp.txt exists: #{exists_temp}")

# Unmount the filesystem
IO.puts("\n6. Unmounting /tmp...")
:ok = Kodo.unmount(:demo, "/tmp")

# List mounts after unmount
{_root2, mounts2} = Kodo.mounts(:demo)
IO.inspect(mounts2, label: "7. Mounts after unmount")

# Verify we can still access root filesystem
{:ok, root_content2} = Kodo.read(:demo, "/root.txt")
IO.puts("   Root file still accessible: #{root_content2}")

# Try to access unmounted filesystem (should fail)
case Kodo.read(:demo, "/tmp/temp.txt") do
  {:ok, _} -> IO.puts("   ERROR: Should not be able to read from unmounted filesystem!")
  {:error, _} -> IO.puts("   ✓ Correctly cannot access unmounted filesystem")
end

# Clean up
Kodo.stop(:demo)
IO.puts("\n✅ VFS mount/unmount demo completed successfully!")
