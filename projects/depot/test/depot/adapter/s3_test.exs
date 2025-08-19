defmodule Depot.Adapter.S3Test do
  use ExUnit.Case
  import Depot.AdapterTest

  setup do
    config = DepotTest.Minio.config()
    DepotTest.Minio.clean_bucket("default")
    DepotTest.Minio.recreate_bucket("default")

    on_exit(fn ->
      DepotTest.Minio.clean_bucket("default")
    end)

    {:ok, config: config, bucket: "default"}
  end

  adapter_test %{config: config} do
    filesystem = Depot.Adapter.S3.configure(config: config, bucket: "default")
    {:ok, filesystem: filesystem}
  end

  describe "cross bucket" do
    setup %{config: config} do
      config_b = DepotTest.Minio.config()
      DepotTest.Minio.clean_bucket("secondary")
      DepotTest.Minio.recreate_bucket("secondary")

      on_exit(fn ->
        DepotTest.Minio.clean_bucket("secondary")
      end)

      {:ok, config_a: config, config_b: config_b}
    end

    test "copy", %{config_a: config_a, config_b: config_b} do
      filesystem_a = Depot.Adapter.S3.configure(config: config_a, bucket: "default")
      filesystem_b = Depot.Adapter.S3.configure(config: config_b, bucket: "secondary")

      :ok = Depot.write(filesystem_a, "test.txt", "Hello World")

      assert :ok =
               Depot.copy_between_filesystem(
                 {filesystem_a, "test.txt"},
                 {filesystem_b, "other.txt"}
               )

      assert {:ok, "Hello World"} = Depot.read(filesystem_b, "other.txt")
    end
  end
end
