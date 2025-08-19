# Advanced Filesystem Operations Demo
# Demonstrates the new advanced filesystem operations in Kodo VFS

# Start an instance
{:ok, _pid} = Kodo.start(:advanced_demo)

IO.puts("=== Advanced Filesystem Operations Demo ===")

# Create test content
IO.puts("\n1. Setting up test files...")
:ok = Kodo.write(:advanced_demo, "demo.txt", "Hello, World! This is a test file.")
:ok = Kodo.write(:advanced_demo, "config.json", "{\"version\": \"1.0\", \"debug\": true}")

# Test stat/2 - Get file metadata
IO.puts("\n2. Testing stat/2 - File metadata:")
{:ok, stat} = Kodo.stat(:advanced_demo, "demo.txt")
IO.puts("   File: #{stat.name}")
IO.puts("   Size: #{stat.size} bytes")
IO.puts("   Visibility: #{stat.visibility}")
IO.puts("   Modified: #{stat.mtime}")

# Test access/3 - Check permissions
IO.puts("\n3. Testing access/3 - Permission checks:")
read_result = Kodo.access(:advanced_demo, "demo.txt", [:read])
write_result = Kodo.access(:advanced_demo, "demo.txt", [:write])
both_result = Kodo.access(:advanced_demo, "demo.txt", [:read, :write])
IO.puts("   Read access: #{inspect(read_result)}")
IO.puts("   Write access: #{inspect(write_result)}")
IO.puts("   Read+Write access: #{inspect(both_result)}")

# Test append/3 - Append content
IO.puts("\n4. Testing append/3 - Append content:")
IO.puts("   Original content:")
{:ok, original} = Kodo.read(:advanced_demo, "demo.txt")
IO.puts("   \"#{original}\"")

:ok = Kodo.append(:advanced_demo, "demo.txt", "\nAppended line 1.")
:ok = Kodo.append(:advanced_demo, "demo.txt", "\nAppended line 2.")

IO.puts("   After appending:")
{:ok, appended} = Kodo.read(:advanced_demo, "demo.txt")
IO.puts("   \"#{appended}\"")

# Test truncate/3 - Resize file
IO.puts("\n5. Testing truncate/3 - Resize file:")
{:ok, before_truncate} = Kodo.read(:advanced_demo, "demo.txt")
IO.puts("   Before truncate (#{byte_size(before_truncate)} bytes): \"#{before_truncate}\"")

:ok = Kodo.truncate(:advanced_demo, "demo.txt", 20)
{:ok, after_truncate} = Kodo.read(:advanced_demo, "demo.txt")
IO.puts("   After truncate to 20 bytes: \"#{after_truncate}\"")

# Test utime/3 - Update modification time
IO.puts("\n6. Testing utime/3 - Update modification time:")
{:ok, stat_before} = Kodo.stat(:advanced_demo, "demo.txt")
IO.puts("   Modification time before: #{stat_before.mtime}")

future_time = DateTime.utc_now() |> DateTime.add(3600, :second) # 1 hour in the future
:ok = Kodo.utime(:advanced_demo, "demo.txt", future_time)

{:ok, stat_after} = Kodo.stat(:advanced_demo, "demo.txt")
IO.puts("   Modification time after: #{stat_after.mtime}")

# Demonstrate with Local filesystem mount
IO.puts("\n7. Testing with Local filesystem mount:")
local_path = System.tmp_dir!() |> Path.join("kodo_advanced_demo")
File.mkdir_p!(local_path)

:ok = Kodo.mount(:advanced_demo, "/local", Depot.Adapter.Local, prefix: local_path)
:ok = Kodo.write(:advanced_demo, "/local/local_file.txt", "This is a local file.")

{:ok, local_stat} = Kodo.stat(:advanced_demo, "/local/local_file.txt")
IO.puts("   Local file size: #{local_stat.size} bytes")
IO.puts("   Local file visibility: #{local_stat.visibility}")

:ok = Kodo.append(:advanced_demo, "/local/local_file.txt", "\nLocal append works too!")
{:ok, local_content} = Kodo.read(:advanced_demo, "/local/local_file.txt")
IO.puts("   Local file content: \"#{local_content}\"")

# Show all mounted filesystems
IO.puts("\n8. Current VFS mounts:")
{root_fs, mounts} = Kodo.mounts(:advanced_demo)
IO.puts("   Root filesystem: #{inspect(root_fs)}")
for {mount_point, filesystem} <- mounts do
  IO.puts("   #{mount_point}: #{inspect(filesystem)}")
end

# Show available operations
IO.puts("\n9. Available advanced operations:")
IO.puts("   - Kodo.stat/2      : Get file/directory metadata")
IO.puts("   - Kodo.access/3    : Check read/write permissions")
IO.puts("   - Kodo.append/3    : Append content to files")
IO.puts("   - Kodo.truncate/3  : Resize files to specific byte count")
IO.puts("   - Kodo.utime/3     : Update file modification time")

# Cleanup
File.rm_rf!(local_path)
Kodo.stop(:advanced_demo)

IO.puts("\n=== Demo complete ===")
IO.puts("All advanced filesystem operations are now available through:")
IO.puts("- Kodo.VFS module (mid-level API)")
IO.puts("- Kodo module (top-level API)")
IO.puts("- Support for InMemory, Local, Git, and GitHub adapters")
