import gleam/dynamic/decode
import gleeunit
import yaya

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn parse_multiple_key_values_test() {
  let yaml =
    "name: Robert
kind: Human"
  let decoder = {
    use name <- decode.field("name", decode.string)
    use kind <- decode.field("kind", decode.string)
    decode.success(name <> ";" <> kind)
  }
  let result = yaya.parse(from: yaml, using: decoder)

  assert result == Ok("Robert;Human")
}

pub fn parse_nested_objects_test() {
  let yaml =
    "robert:
  kind: human
lucy:
  kind: starfish"

  let kind_decoder = decode.field("kind", decode.string, decode.success)
  let decoder = {
    use robert_kind <- decode.field("robert", kind_decoder)
    use lucy_kind <- decode.field("lucy", kind_decoder)
    decode.success(#(robert_kind, lucy_kind))
  }
  let r = yaya.parse(yaml, decoder)
  assert r == Ok(#("human", "starfish"))
}
