defmodule Jido.AI.CoverageConfigTest do
  use ExUnit.Case, async: true

  test "mix project enforces 90 percent coverage threshold" do
    coverage_config = Mix.Project.config()[:test_coverage]

    assert coverage_config[:tool] == ExCoveralls
    assert coverage_config[:summary][:threshold] == 90
  end

  test "coveralls config enforces runtime-focused coverage scope" do
    config = File.read!("coveralls.json") |> Jason.decode!()

    assert config["coverage_options"]["minimum_coverage"] == 90

    assert "^examples/" in config["skip_files"]
    refute "^lib/mix/tasks/" in config["skip_files"]
    assert "^test/support/" in config["skip_files"]
  end
end
