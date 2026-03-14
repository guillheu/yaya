import gleam/dict.{type Dict}
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/time/duration
import gleam/time/timestamp.{type Timestamp}
import internal/lexer

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
  UnableToDecode(List(decode.DecodeError))
}

pub fn parse(
  from yaml: String,
  using decoder: decode.Decoder(t),
) -> Result(t, DecodeError) {
  let r =
    yaml
    |> lexer.run_lexer
    |> private_parse
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
    // { "!!timestamp " <> timestamp.to_rfc3339(value, duration.seconds(0)) }
    // |> dynamic.string
  }
}

fn pair_to_dynamics(value: #(Yaml, Yaml)) -> #(Dynamic, Dynamic) {
  let first = to_dynamic(value.0)
  let second = to_dynamic(value.1)
  #(first, second)
}

fn private_parse(list: List(lexer.YamlToken)) -> Result(Yaml, DecodeError) {
  todo
}
