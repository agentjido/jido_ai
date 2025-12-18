## v2.1.0 - 2025-11-03

### 🚀 Features

- add :private option to use defparsecp @lud (#101)

## v2.0.0 - 2025-03-05

### Highlights 🎉

- Core rules are no longer special-cased, they are brought in via parsing and compiling `core.abnf`
  - hence they can now be transformed, ignored, just like other rules
- Core rules are now all transformed to string format by default
  - so when matching `*HEXDIG` on `"1A"`, instead of getting `[49, 65]`, you get `["1", "A"]`
  - however, performing `List.to_string` on either one gives you the same result - `"1A"`
- Core rules are defined only when they are not already defined in your abnf
  - if they are already defined in your abnf, they will be skipped
  - note the way we generate the functions unifies cases, so if you have `char` defined,
    the core rule `CHAR` will be ignored as well
  - this also makes it possible to override core rules

## v1.3.0 - 2025-01-30

- Add byte mode to generate parsers that work on byte representation instead of text codepoints

## v1.2.6 - 2025-01-29

- support utf-8 codepoint sequence

## v1.2.5 - 2025-01-29

### 🐛 Bug Fixes

- Fix core rule HEXDIG to allow lowercase chars

## v1.2.4 - 2025-01-28

### 🐛 Bug Fixes

- Fix nimble parsec deprecation warnings @sax (#82)

## v1.2.3 - 2025-01-06

### Fixed

- Generate utf8 matcher instead of ascii on num_range (c40c2b9) fix [#76](https://github.com/princemaple/abnf_parsec/issues/76)

## v1.2.1 - 2022-02-05

### Fixed

- String concatenation bug caused by case insensitivity implementation

## v1.2.0 - 2021-03-17

### Changed

Now strings default to be case insensitive

## v1.1.0 - 2020-12-28

### 🚀 Features

- Rfc7405 @guenni68 (#16)
  - Adds case-insensitive string matching but haven't switched default to case-insensitive yet

## v1.0.0 - 2020-11-03

Not much, just that it's stable enough

--------------------
[pre-1.0 CHANGELOG](https://github.com/princemaple/abnf_parsec/blob/v1.0.0/CHANGELOG.md)
