{:ok, _} = DepotTest.Minio.start_link()
Process.sleep(1000)
DepotTest.Minio.initialize_bucket("default")
ExUnit.start()
