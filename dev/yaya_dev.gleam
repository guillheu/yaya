import gleam/dict
import gleam/dynamic/decode
import gleam/io
import gleam/json
import simplifile
import yaya

type Data {
  Data(one: String, two: String)
}

fn data_to_json(data: Data) -> json.Json {
  let Data(one:, two:) = data
  json.object([
    #("one", json.string(one)),
    #("two", json.string(two)),
  ])
}

fn data_decoder() -> decode.Decoder(Data) {
  use one <- decode.field("1", decode.string)
  use two <- decode.field("2", decode.string)
  decode.success(Data(one:, two:))
}

pub fn main() {
  Nil
}
