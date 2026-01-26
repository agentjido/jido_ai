# Credo Configuration File

%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      checks: %{
        # Disable specific checks
        disabled: [
          # Logger metadata keys are used at runtime for dynamic logging
          {Credo.Check.Warning.MissedMetadataKeyInLoggerConfig, []}
        ]
      }
    }
  ]
}
