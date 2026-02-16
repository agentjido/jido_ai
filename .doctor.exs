%Doctor.Config{
  ignore_modules: [],
  ignore_paths: [
    ~r"lib/jido_ai/agents/examples/",
    ~r"lib/jido_ai/examples/"
  ],
  min_module_doc_coverage: 60,
  min_module_spec_coverage: 0,
  min_overall_doc_coverage: 90,
  min_overall_moduledoc_coverage: 100,
  min_overall_spec_coverage: 0,
  exception_moduledoc_required: true,
  raise: false,
  reporter: Doctor.Reporters.Summary,
  struct_type_spec_required: false,
  umbrella: false
}
