import gleam/list
import gleam/string

pub type YamlToken {
  Colon
  Text(String)
  DoubleQuote
  SingleQuote
  NewLine(indent: Int)
  Hyphen

  // UNIMPLEMENTED TOKENS------------------------------------------
  // Document Structure
  DocumentStart
  DocumentEnd
  Directive(String)

  // Json-like syntax
  QuestionMark
  SquareBracketsOpen
  SquareBracketsClose
  CurlyBracketsOpen
  CurlyBracketsClose
  Comma

  // Text
  TextBlockKeepNewLines(String)
  TextBlockFoldNewLines(String)

  // Other
  Anchor
  Alias
  TypeTag
  Comment(String)
}

pub fn run_lexer(from: String) -> List(YamlToken) {
  run_lexer_recurse(from, [], NewLine(0)) |> list.reverse
}

fn run_lexer_recurse(
  from: String,
  acc: List(YamlToken),
  last_token: YamlToken,
) -> List(YamlToken) {
  case from {
    ":" <> rest -> run_lexer_recurse(rest, [last_token, ..acc], Colon)
    "\"" <> rest -> run_lexer_recurse(rest, [last_token, ..acc], DoubleQuote)
    "'" <> rest -> run_lexer_recurse(rest, [last_token, ..acc], SingleQuote)
    "\n" <> rest -> run_lexer_recurse(rest, [last_token, ..acc], NewLine(0))
    " " <> rest ->
      case last_token {
        NewLine(n) -> run_lexer_recurse(rest, acc, NewLine(n + 1))
        Comment(content) ->
          run_lexer_recurse(rest, acc, Comment(content <> " "))
        _other -> run_lexer_recurse(rest, acc, last_token)
      }
    "-" <> rest -> run_lexer_recurse(rest, [last_token, ..acc], Hyphen)
    "#" <> rest -> run_lexer_recurse(rest, [last_token, ..acc], Comment(""))
    "" -> [last_token, ..acc]
    other -> {
      let assert Ok(next_char) = string.first(other)
      // Asserting here because if it was an empty string
      // it was already caught in the `""` case previously.
      // Yes this is an anti-pattern. Should be fixed by using
      // a BitArray input, instead of a String
      let rest = string.slice(other, 1, string.length(other) - 1)
      case last_token {
        Text(previous_text) ->
          run_lexer_recurse(rest, acc, Text(previous_text <> next_char))
        Comment(content) ->
          run_lexer_recurse(rest, acc, Comment(content <> next_char))
        _other -> run_lexer_recurse(rest, [last_token, ..acc], Text(next_char))
      }
    }
  }
}
