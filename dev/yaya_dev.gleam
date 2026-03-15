import gleam/dynamic/decode
import internal/lexer
import simplifile
import yaya

pub fn main() {
  let assert Ok(content) = simplifile.read("data.yaml")

  yaya.parse_to_yaml(content) |> echo

  // let assert Ok(parsed) = yaya.parse(content, data_decoder())
  // echo parsed
  Nil
}
