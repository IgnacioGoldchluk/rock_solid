[![CI](https://github.com/IgnacioGoldchluk/rock_solid/actions/workflows/ci.yaml/badge.svg)](https://github.com/IgnacioGoldchluk/rock_solid/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/rock_solid)](https://github.com/IgnacioGoldchluk/rock_solid/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/rock_solid.svg)](https://hex.pm/packages/rock_solid)
[![Docs](https://img.shields.io/badge/documentation-gray.svg)](https://rock-solid.hexdocs.pm)

Data generation from JSON schema. Supports JSON Schema draft 04 to draft 2020-12.

## Usage
Add to your list of dependencies
```elixir
def deps do
  [
    {:rock_solid, "~> 0.0.11", only: :test}
  ]
end
```

Inside a `property` test
```elixir
defmodule MyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "generates valid user profiles" do
    schema = %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "birthDate" => %{"type" => "string", "format" => "date"},
        "name" => %{"type" => "string", "pattern" => "^[A-Z][a-z]+$"},
        "email" => %{"type" => "string", "format" => "email"}
      },
      "required" => ["birthDate", "name", "email"]
    }

    check all user_data <- RockSolid.from_schema(schema) do
      assert Regex.match?(~r/^[A-Z][a-z]+$/, user_data["name"])
      assert %Date{} = Date.from_iso8601!(user_data["birthDate"])
      assert String.split(user_data["email"], "@") |> length() == 2
    end
  end
end
```

or as a generator, since `RockSolid.from_schema/2` returns elements of `StreamData.t()`

```elixir
iex(1)> specs = %{
  "type" => "object",
  "properties" => %{
    "serverIPs" => %{
      "type" => "array",
      "items" => %{"type" => "string", "format" => "ipv4"},
      "uniqueItems" => true,
      "minItems" => 1
    },
    "serverName" => %{"pattern" => "^[a-z][a-z_0-9]{2,255}$", "type" => "string"},
  },
  "required" => ["serverIPs", "serverName"],
  "additionalProperties" => false
}

iex(2)> specs |> RockSolid.from_schema() |> Enum.take(3)
[
  %{"serverIPs" => ["148.50.92.205"], "serverName" => "a5l"},
  %{"serverIPs" => ["230.26.166.121"], "serverName" => "y_w"},
  %{
    "serverIPs" => ["144.154.111.248", "155.134.134.38"],
    "serverName" => "v2_5"
  }
]
```

## Knwon bugs and issues
The library can generate valid payloads for most schemas, with a 87% passing rate when testing the entire catalog from [Schemastore](https://github.com/SchemaStore/schemastore). The following are a list of known bugs, limitations and issues, ordered from most common to least common.
- Failing to generate data when possible value set is too narrow. For example strings with `"pattern"` and `minLength`/`maxLength`, or a `not` clause that overlaps with many of the positive cases. To prevent this issue, encode the string length as part of the `"pattern"` keyword, and try to be specific when using `"not"` keywords. 
- Timemouts. Caused when defining multiple `"if"/"then"/"else"`, `"dependentSchemas"`, and `"oneOf"`. To prevent timeouts, express branching logic as `"anyOf"` instead.
- Recursive schemas. While recursive schemas are supported, the algorithm often needs to find the intersection of a recursive schema and another subschema, which might throw an error. There is no workaround for this issue at the moment.
- `"$dynamicRef"`, `"$dynamicAnchor"`, `"unevaluatedItems"`, `"unevaluatedProperties"`, `"maxContains"` keywords are not supported currently, since their behavior is defined at runtime.
