import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import internal/lexer.{
  Colon, Comment, DoubleQuote, Hyphen, NewLine, SingleQuote, Text,
}

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
  |> parse_to_yaml_recurse(YamlMap([]), 0)
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
  list: List(lexer.YamlToken),
  current_yaml: Yaml,
  current_indent: Int,
) -> Result(#(Yaml, List(lexer.YamlToken)), DecodeError) {
  case list {
    [NewLine(indent), ..rest] if indent < current_indent ->
      Ok(#(current_yaml, rest))

    //
    // "\n  text_key: text_value"
    [NewLine(indent), Text(key_str), Colon, Text(value_str), ..rest]
      if indent == current_indent
    -> {
      let assert YamlMap(keyed_list) = current_yaml
      let key = parse_string_token(key_str)
      let val = parse_string_token(value_str)
      let new_keyed_list = list.append(keyed_list, [#(key, val)])
      let new_current_yaml = YamlMap(new_keyed_list)
      parse_to_yaml_recurse(rest, new_current_yaml, indent)
    }

    //
    // "\n  text_key:\n    "
    [
      NewLine(indent_this_line),
      Text(key_str),
      Colon,
      NewLine(indent_next_line),
      ..rest
    ]
      if indent_this_line == current_indent
    -> {
      let assert YamlMap(keyed_list) = current_yaml
      let r =
        parse_to_yaml_recurse(
          [NewLine(indent_next_line), ..rest],
          YamlMap([]),
          indent_next_line,
        )
      use #(field_value, rest) <- result.try(r)
      let new_keyed_list =
        list.append(keyed_list, [#(YamlString(key_str), field_value)])
      let new_current_yaml = YamlMap(new_keyed_list)
      parse_to_yaml_recurse(rest, new_current_yaml, indent_this_line)
    }

    //
    // Comments are ignored
    [Comment(_), ..rest] ->
      parse_to_yaml_recurse(rest, current_yaml, current_indent)

    //
    // empty, final return
    [] -> Ok(#(current_yaml, []))

    //
    // unknown, unhandled
    other ->
      Error(
        todo as {
          "unimplemented parsing case or parsing error: "
          <> string.inspect(other)
        },
      )
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
