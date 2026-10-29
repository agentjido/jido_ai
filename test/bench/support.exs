support = Path.join(__DIR__, "support")

for file <- [
      "react.ex",
      "react/extended_react.ex",
      "react/fixtures.ex",
      "react/model.ex",
      "react/memory_sampler.ex",
      "react/fact_trace.ex",
      "react/probe.ex",
      "react/report.ex"
    ] do
  Code.require_file(Path.join(support, file))
end

Req.Test.set_req_test_to_shared()
