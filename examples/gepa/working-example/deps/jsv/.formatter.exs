public_macros = [defschema: 1, defschema: 2, defschema: 3, defschema_for: 2, defcast: 1, defcast: 2, defcast: 3]

# Used by "mix format"
[
  line_length: 120,
  import_deps: [:readmix],
  inputs: ["*.exs", "{config,lib,test,tools,tmp,dev}/**/*.{ex,exs}"],
  force_do_end_blocks: true,
  locals_without_parens:
    public_macros ++
      [
        pass: 1,
        passp: 1,
        ignore_keyword: 1,
        take_keyword: 5,
        take_keyword: 6,
        consume_keyword: 1,
        defcompose: 2,
        defpreset: 2,
        with_decimal: 1,
        debang: 1
      ],
  export: [locals_without_parens: public_macros]
]
