Mix.install([{:depot, path: "../depot"}])
Code.require_file("lib/kodo.ex")
Code.require_file("lib/kodo/application.ex")
Application.ensure_all_started(:kodo)

# Test the main API
{:ok, _} = Kodo.start(:test_instance)
IO.puts("✓ Started instance")

:ok = Kodo.write(:test_instance, "/hello.txt", "Hello VFS!")
IO.puts("✓ Wrote file")

{:ok, content} = Kodo.read(:test_instance, "/hello.txt")
IO.puts("✓ Read content: #{content}")

{:ok, mounts} = Kodo.mounts(:test_instance)
IO.puts("✓ Listed mounts: #{length(mounts)} mount(s)")

{:ok, files} = Kodo.ls(:test_instance, "/")
IO.puts("✓ Listed files: #{length(files)} file(s)")

:ok = Kodo.mount(:test_instance, "/data", Depot.Adapter.InMemory, name: :DataFS)
IO.puts("✓ Mounted additional filesystem")

:ok = Kodo.write(:test_instance, "/data/test.txt", "Data filesystem test")
IO.puts("✓ Wrote to mounted filesystem")

{:ok, data_content} = Kodo.read(:test_instance, "/data/test.txt")
IO.puts("✓ Read from mounted filesystem: #{data_content}")

{:ok, new_mounts} = Kodo.mounts(:test_instance)
IO.puts("✓ Listed mounts after mount: #{length(new_mounts)} mount(s)")

:ok = Kodo.unmount(:test_instance, "/data")
IO.puts("✓ Unmounted filesystem")

IO.puts("\n🎉 All VFS operations working correctly!")
