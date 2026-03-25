import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import internal/lexer.{
  Colon, Comment, DoubleQuote, Hyphen, NewLine, SingleQuote, Text,
}

// TODO:
// Lexer should return a lines: List(#(indent: Int, tokens: List(YamlToken)))
// Parser should parse over each line to easily find impossible states
// Accumulator should be a STACK of tasks.
// Need a custom task type, because there are 2 tasks:
// - sequences
// - maps
// so in the parsing function, we case match against the current task
// and we ensure the tokens we find (hyphens etc) match the task we're working on.
// This also means we can have no task going on, in which case... idk yet

pub opaque type Yaml {
  // dynamic.properties
  YamlMap(List(#(Yaml, Yaml)))
  // dynamic.lits
  YamlArray(List(Yaml))
  // dynamic.int
  YamlInt(Int)
  // dynamic.string
  YamlString(String)
  // dynamic.float
  YamlFloat(Float)
  // dynamic.string("+.inf" / "-.inf")
  YamlInfinity(positive: Bool)
  // dynamic.string("NaN")
  YamlNaN
  // dynamic.bool
  YamlBool(Bool)
  // dynamic.nil
  YamlNull
  // dynamic.bitarray
  YamlBinary(BitArray)
  // ???
  YamlDate(Timestamp)
}

pub type DecodeError {
  UnexpectedToken(lexer.YamlToken)
  InvalidFormat(explanaition: String)
  EmptyYamlDocument
  InvalidIndent
  UnableToDecode(List(decode.DecodeError))
}

pub fn parse(
  from yaml: String,
  using decoder: decode.Decoder(t),
) -> Result(t, DecodeError) {
  let r =
    yaml
    |> parse_to_yaml
  use decoded_yaml <- result.try(r)
  to_dynamic(decoded_yaml)
  |> echo
  |> decode.run(decoder)
  |> result.map_error(UnableToDecode)
}

pub fn parse_bits(
  from yaml: BitArray,
  using decoder: decode.Decoder(t),
) -> Result(t, decode.DecodeError) {
  todo
}

pub fn parse_to_yaml(from yaml: String) -> Result(Yaml, DecodeError) {
  lexer.run_lexer(yaml)
  |> parse_to_yaml_recurse(None, 0, [])
  |> result.map(fn(ret) {
    let #(yaml, _) = ret
    yaml
  })
}

pub fn to_string(yaml: Yaml) -> String {
  todo
}

pub fn to_string_tree(yaml: Yaml) -> String {
  todo
}

// Yaml creators

pub fn array(from entries: List(a), of inner_type: fn(a) -> Yaml) -> Yaml {
  list.map(entries, inner_type)
  |> YamlArray
}

pub fn bool(input: Bool) -> Yaml {
  YamlBool(input)
}

pub fn dict(
  dict: Dict(k, v),
  keys: fn(k) -> Yaml,
  values: fn(v) -> Yaml,
) -> Yaml {
  dict
  |> dict.to_list
  |> list.map(fn(entry) {
    let #(key, value) = entry
    #(keys(key), values(value))
  })
  |> YamlMap
}

pub fn float(input: Float) -> Yaml {
  YamlFloat(input)
}

pub fn int(input: Int) -> Yaml {
  YamlInt(input)
}

pub fn null() -> Yaml {
  YamlNull
}

pub fn nullable(from input: Option(a), of inner_type: fn(a) -> Yaml) -> Yaml {
  case input {
    option.Some(value) -> inner_type(value)
    option.None -> YamlNull
  }
}

pub fn object(entries: List(#(Yaml, Yaml))) -> Yaml {
  YamlMap(entries)
}

pub fn preprocessed_array(from: List(Yaml)) -> Yaml {
  YamlArray(from)
}

pub fn string(input: String) -> Yaml {
  YamlString(input)
}

pub fn timestamp(input: Timestamp) -> Yaml {
  YamlDate(input)
}

pub fn binary(input: BitArray) -> Yaml {
  YamlBinary(input)
}

// Private functions

// This does not implement TCO but it really should.
// How to use an accumulator when `dynamic.properties` 
// requires turning keys and values into dynamics first?
fn to_dynamic(yaml: Yaml) -> Dynamic {
  case yaml {
    YamlMap(value) -> list.map(value, pair_to_dynamics) |> dynamic.properties
    YamlArray(value) -> list.map(value, to_dynamic) |> dynamic.list
    YamlInt(value) -> dynamic.int(value)
    YamlString(value) -> dynamic.string(value)
    YamlFloat(value) -> dynamic.float(value)
    YamlBool(value) -> dynamic.bool(value)
    YamlNull -> dynamic.nil()
    YamlBinary(value) -> dynamic.bit_array(value)
    YamlDate(value) -> todo as "Yaml date not yet implemented"
    YamlInfinity(positive:) if positive -> dynamic.string("+.inf")
    YamlInfinity(_) -> dynamic.string("-.inf")
    YamlNaN -> dynamic.string("NaN")
    // { "!!timestamp " <> timestamp.to_rfc3339(value, duration.seconds(0)) }
    // |> dynamic.string
  }
}

fn pair_to_dynamics(value: #(Yaml, Yaml)) -> #(Dynamic, Dynamic) {
  let first = to_dynamic(value.0)
  let second = to_dynamic(value.1)
  #(first, second)
}

fn parse_to_yaml_recurse(
  // List of lines.
  // Each line has an indent and a list of tokens
  lines: List(#(Int, List(lexer.YamlToken))),
  current_yaml: Option(Yaml),
  previous_indent: Int,
  tasks_stack: List(#(Int, fn(Yaml) -> Yaml)),
) -> Result(#(Yaml, List(lexer.YamlToken)), DecodeError) {
  case lines, current_yaml {
    //
    // STAYING IN THE SAME OBJECT
    [#(indent, tokens), ..lines_rest], _ if indent == previous_indent ->
      found_line_same_indent(
        tokens,
        current_yaml,
        lines_rest,
        indent,
        tasks_stack,
        previous_indent,
      )

    // NESTING INTO A DEEPER OBJECT
    [#(indent, tokens), ..lines_rest], None if indent > previous_indent ->
      case tokens {
        [Text(_), Colon, ..rest] ->
          parse_to_yaml_recurse(lines, Some(YamlMap([])), indent, tasks_stack)
        _ -> todo
      }

    // Nesting, but still working on a yaml. ERROR
    [#(indent, tokens), ..lines_rest], Some(_) if indent > previous_indent ->
      found_line_higher_indent_unexpected()

    // FINISHED NESTED OBJECT, GOING BACK UP
    [#(indent, tokens), ..lines_rest], Some(current_yaml)
      if indent < previous_indent
    -> {
      found_line_lower_indent(tasks_stack, indent, current_yaml, lines)
    }

    // Going back up without starting an expected yaml,
    // meaning the top of the stack gets a null yaml value
    [#(indent, tokens), ..lines_rest], None if indent < previous_indent -> todo

    [], Some(yaml) -> {
      Ok(#(yaml, []))
    }
    [], None -> Error(EmptyYamlDocument)
    _, _ ->
      panic as "unreachable code. How can an int be neither ==, <= or >= to another?"
  }
}

fn found_line_higher_indent_unexpected() -> Result(
  #(Yaml, List(lexer.YamlToken)),
  DecodeError,
) {
  Error(InvalidIndent)
}

fn found_line_lower_indent(
  tasks_stack: List(#(Int, fn(Yaml) -> Yaml)),
  indent: Int,
  current_yaml: Yaml,
  lines: List(#(Int, List(lexer.YamlToken))),
) -> Result(#(Yaml, List(lexer.YamlToken)), DecodeError) {
  case tasks_stack {
    [#(task_indent, task_function), ..tasks_rest] if indent <= task_indent -> {
      let higher_yaml = task_function(current_yaml)
      parse_to_yaml_recurse(lines, Some(higher_yaml), task_indent, tasks_rest)
    }
    _ ->
      todo as "should throw an error because that means having a high indent first into a low indent"
  }
}

fn found_line_same_indent(
  tokens: List(lexer.YamlToken),
  current_yaml: Option(Yaml),
  lines_rest: List(#(Int, List(lexer.YamlToken))),
  indent: Int,
  tasks_stack: List(#(Int, fn(Yaml) -> Yaml)),
  previous_indent: Int,
) -> Result(#(Yaml, List(lexer.YamlToken)), DecodeError) {
  case tokens {
    // Flat map, just append to existing map
    [Text(key_str), Colon, Text(value_str)] -> {
      let r = case current_yaml {
        Some(YamlMap(keyed_list)) -> Ok(keyed_list)
        None -> Ok([])
        _ ->
          Error(InvalidFormat(
            "Expected line contains a mapping, but we were previously evaluating something that's not a mapping",
          ))
      }
      use keyed_list <- result.try(r)
      let key = parse_string_token(key_str)
      let val = parse_string_token(value_str)
      let new_keyed_list = list.append(keyed_list, [#(key, val)])
      let new_current_yaml = YamlMap(new_keyed_list)
      parse_to_yaml_recurse(
        lines_rest,
        Some(new_current_yaml),
        indent,
        tasks_stack,
      )
    }
    // We expect a nested object. Prepending a task
    [Text(key_str), Colon] -> {
      let r = case current_yaml {
        None -> Ok([])
        Some(YamlMap(contents)) -> Ok(contents)
        _ ->
          Error(InvalidFormat(
            "Found the continuation of a Yaml object (at key \""
            <> key_str
            <> "\"), but the preceding content is not an object (found "
            <> string.inspect(current_yaml)
            <> ")",
          ))
      }
      use previous_yaml_map_content <- result.try(r)
      let new_task = #(indent, fn(value_yaml: Yaml) {
        YamlMap([
          #(parse_string_token(key_str), value_yaml),
          ..previous_yaml_map_content
        ])
      })
      // We prepend a task, don't change the indent, and set the current yaml no None
      // This is because next loop will notice the (normally) higher indent, 
      // and check the current_yaml to see whether we expected to enter a new block
      // if not, then it's an error. If yes, we're just in a nested object and next
      // indent will be set to the new block indent
      parse_to_yaml_recurse(lines_rest, None, indent, [new_task, ..tasks_stack])
    }
    [] ->
      parse_to_yaml_recurse(
        lines_rest,
        current_yaml,
        previous_indent,
        tasks_stack,
      )
    other -> todo as { "unhandled: " <> string.inspect(other) }
  }
}

fn parse_string_token(from: String) -> Yaml {
  case from {
    "true" | "True" | "TRUE" | "yes" | "Yes" | "YES" | "on" | "On" | "ON" ->
      YamlBool(True)
    "false" | "False" | "FALSE" | "no" | "No" | "NO" | "off" | "Off" | "OFF" ->
      YamlBool(False)
    "null" | "Null" | "NULL" | "~" -> YamlNull
    ".inf" | ".Inf" | ".INF" | "+.inf" | "+.Inf" | "+.INF" -> YamlInfinity(True)
    "-.inf" | "-.Inf" | "-.INF" -> YamlInfinity(False)
    ".nan" | ".NaN" | ".NAN" -> YamlNaN
    "0x" <> hex_string ->
      int.base_parse(hex_string, 16)
      |> result.map(YamlInt)
      |> result.unwrap(YamlString(from))
    other -> {
      case int.parse(other) {
        Ok(int_value) -> YamlInt(int_value)
        Error(_) ->
          case float.parse(other) {
            Ok(float_value) -> YamlFloat(float_value)
            Error(_) -> YamlString(other)
          }
      }
    }
  }
}
