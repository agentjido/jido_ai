# 0.4.0

- Add `Part.file_content_field` to support in-memory file content (thanks @restlessronin!)

# 0.3.1

- Fix issue overriding `Content-Disposition` header which would create multiple headers (thanks @awea!)

# 0.3.0

- Generate `Content-Length` length correctly, by using bytes, not graphemes
- Fix generation `Content-Disposition` header for text parts
- Allow use of `mime` 2.x if available
- Fix README example

# 0.2.0

- Stream files in binary mode, not line mode, which preserves line breaks and ensures that binary files are not corrupted on output (thanks @xadhoom)

# 0.1.1

- Initial release
