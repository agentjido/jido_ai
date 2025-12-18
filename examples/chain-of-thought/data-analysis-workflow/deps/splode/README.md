# Splode

Splode helps you deal with errors and exceptions in your application that are aggregatable and consistent. The general pattern is that you use the `Splode` module as a top level aggregator of error classes, and whenever you return errors, you return one of your `Splode.Error` structs, or a string, or a keyword list. Then, if you want to group errors together, you can use your `Splode` module to do so. You can also use that module to turn any arbitrary value into a splode error.

See the [documentation on hex](https://hexdocs.pm/splode) for more information
