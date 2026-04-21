# YAYA
### Yet Another Yaml Again

## TODO
- implement many, many, many more test cases. Ideally use some existing tests suites.
- TCO for lexer
- TCO for `to_dynamic`
- lexer should start by splitting the input string into lines
- lexer should run over bit arrays, not strings.

## Questions to answer:
- How to handle document start `---` and end `---`? This would be like having multiple json declarations in a single json file. I think it should be unsupported, or alternatively yaya could always return an array of yaml documents, and let the user decode each document into its expected type
- Where do we draw the line of things to support or not? For a version 1.0 I think the full spec should be covered, but in general I'd be content with supporting a subset of all tokens. I'm not sure yet.
- How should we benchmark yaya against existing erlang and javascript yaml parsers?