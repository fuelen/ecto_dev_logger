defmodule Ecto.DevLogger.PrintableParameterTest do
  use ExUnit.Case, async: true
  doctest Ecto.DevLogger.PrintableParameter
  import Ecto.DevLogger.PrintableParameter

  test "to_expression/1" do
    # NULL
    assert to_expression(nil) == "NULL"

    # Boolean
    assert to_expression(true) == "true"
    assert to_expression(false) == "false"

    # Atom
    assert to_expression(:hey) == "'hey'"
    assert to_expression(:hey@hey) == "'hey@hey'"

    # Integer
    assert to_expression(-123) == "-123"
    assert to_expression(123) == "123"

    # Float
    assert to_expression(123.12) == "123.12"
    assert to_expression(-123.12) == "-123.12"

    # Decimal
    assert to_expression(Decimal.from_float(-123.12)) == "-123.12"
    assert to_expression(Decimal.from_float(123.12)) == "123.12"

    # String
    assert to_expression("string with single quote: '") == ~s|'string with single quote: '''|
    assert to_expression("string with double quote: \"") == ~s|'string with double quote: "'|
    assert to_expression("") == ~s|''|

    # Binary
    assert to_expression(<<95, 131, 49, 101, 176, 212, 77, 86>>) ==
             "DECODE('X4MxZbDUTVY=','BASE64')"

    # Map
    assert to_expression(%{
             "string" => "string",
             "boolean" => true,
             "integer" => 1,
             "array" => [1, 2, 3]
           }) == ~s|'{"array":[1,2,3],"boolean":true,"integer":1,"string":"string"}'|

    # UUID-like binary
    assert to_expression(
             <<220, 46, 200, 4, 110, 226, 70, 137, 168, 241, 190, 89, 170, 128, 119, 31>>
           ) == "'dc2ec804-6ee2-4689-a8f1-be59aa80771f'"

    # Date and Time
    assert to_expression(~D[2022-11-04]) == "'2022-11-04'"
    assert to_expression(~U[2022-11-04 10:40:11.362181Z]) == "'2022-11-04 10:40:11.362181Z'"
    assert to_expression(~N[2022-11-04 10:40:01.256931]) == "'2022-11-04 10:40:01.256931'"
    assert to_expression(~T[10:40:17.657300]) == "'10:40:17.657300'"

    # Postgrex types
    assert to_expression(%Postgrex.INET{address: {127, 0, 0, 1}, netmask: 24}) == "'127.0.0.1/24'"
    assert to_expression(%Postgrex.INET{address: {127, 0, 0, 1}, netmask: nil}) == "'127.0.0.1'"
    assert to_expression(%Postgrex.MACADDR{address: {8, 1, 43, 5, 7, 9}}) == "'08:01:2B:05:07:09'"

    # List
    assert to_expression([]) == "'{}'"
    assert to_expression([1, 2, 3]) == "'{1,2,3}'"
    assert to_expression([1, 2, 3, nil]) == ~s|'{1,2,3,NULL}'|
    assert to_expression([1.2, 2.3, 3.4]) == "'{1.2,2.3,3.4}'"
    assert to_expression(["abc", "DFG", "NULL", ""]) == ~s|'{abc,DFG,"NULL",""}'|
    assert to_expression([:hello, :world]) == ~s|'{hello,world}'|
    assert to_expression(["single quote:'"]) == "'{single quote:''}'"
    assert to_expression(["double quote:\""]) == ~s|'{double quote:\\"}'|
    assert to_expression(["{", "}", ","]) == ~s|'{"{","}",","}'|
    assert to_expression([[1, 2, 3], [3, 4, 5]]) == "'{{1,2,3},{3,4,5}}'"
    assert to_expression([["a", "b", "c"], ["d", "f", "e"]]) == "'{{a,b,c},{d,f,e}}'"
    assert to_expression([~D[2022-11-04], ~D[2022-11-03]]) == "'{2022-11-04,2022-11-03}'"

    assert to_expression([~U[2022-11-04 10:40:11.362181Z], ~U[2022-11-03 10:40:11.362181Z]]) ==
             "'{2022-11-04 10:40:11.362181Z,2022-11-03 10:40:11.362181Z}'"

    assert to_expression([~N[2022-11-04 10:40:01.256931], ~N[2022-11-03 10:40:01.256931]]) ==
             "'{2022-11-04 10:40:01.256931,2022-11-03 10:40:01.256931}'"

    assert to_expression([~T[10:40:17.657300], ~T[09:40:17.657300]]) ==
             "'{10:40:17.657300,09:40:17.657300}'"

    assert to_expression([
             %Postgrex.INET{address: {127, 0, 0, 1}, netmask: 24},
             %Postgrex.INET{address: {127, 0, 0, 1}, netmask: nil}
           ]) == "'{127.0.0.1/24,127.0.0.1}'"

    assert to_expression([%Geo.Point{coordinates: {44.21587, -87.5947}, srid: 4326, properties: %{}}]) ==
      "'{\"%Geo.Point{coordinates: {44.21587, -87.5947}, properties: %{}, srid: 4326}\"}'"

    assert to_expression([%Postgrex.MACADDR{address: {8, 1, 43, 5, 7, 9}}]) ==
             "'{08:01:2B:05:07:09}'"

    # List of lexemes is considered as tsvector
    assert to_expression([
             %Postgrex.Lexeme{word: "Joe's", positions: [{5, :D}]},
             %Postgrex.Lexeme{word: "foo", positions: [{1, :A}, {3, :B}, {2, nil}]},
             %Postgrex.Lexeme{word: "bar", positions: []}
           ]) == "'''Joe''''s'':5 foo:1A,3B,2 bar'"

    assert to_expression([%{}, %{}]) == ~s|'{"{}","{}"}'|
    assert to_expression([{1, "USD"}, {2, "USD"}]) == ~s|'{"(1,USD)","(2,USD)"}'|

    assert to_expression([[<<95, 131, 49, 101>>, <<101, 176, 212, 77, 86>>, nil]]) ==
             "ARRAY[ARRAY[DECODE('X4MxZQ==','BASE64'),DECODE('ZbDUTVY=','BASE64'),NULL]]"

    # Tuple (composite types)
    assert to_expression({1, 1.2, "string", "", nil}) == ~s|'(1,1.2,string,"",)'|

    assert to_expression({"'", ~s|"|, ")", "(", ",", "multiple words"}) ==
             ~s|'('',\\",")","(",",",multiple words)'|

    assert to_expression({{<<101, 49, 95, 131>>, "hello", nil}, {nil, [1, 2, 3]}}) ==
             ~s|ROW(ROW(DECODE('ZTFfgw==','BASE64'),'hello',NULL),'(,"{1,2,3}")')|
  end
end
