# Check the same package surface that ExDoc publishes. Private modules declare
# @moduledoc false; examples are compiled in dev but excluded from package docs.
Mix.Task.run("compile")
Application.load(:jido_ai)
{:ok, package_modules} = :application.get_key(:jido_ai, :modules)

hidden_modules =
  Enum.filter(package_modules, fn module ->
    case Code.fetch_docs(module) do
      {:docs_v1, _, _, _, :hidden, _, _} -> true
      _ -> false
    end
  end)

%Doctor.Config{
  ignore_modules: hidden_modules,
  ignore_paths: [
    ~r"^examples/"
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
