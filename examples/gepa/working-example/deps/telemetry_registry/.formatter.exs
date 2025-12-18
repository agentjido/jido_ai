locals_without_parens = [
  telemetry_event: 1
]

[
  inputs: ["*.{ex,exs}", "{rel,config,lib,test}/**/*.{ex,exs}"],
  subdirectories: [],
  locals_without_parens: locals_without_parens,
  export: [
    locals_without_parens: locals_without_parens
  ]
]
