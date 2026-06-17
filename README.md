[![CI](https://github.com/IgnacioGoldchluk/rock_solid/actions/workflows/ci.yaml/badge.svg)](https://github.com/IgnacioGoldchluk/rock_solid/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/rock_solid)](https://github.com/IgnacioGoldchluk/rock_solid/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/rock_solid.svg)](https://hex.pm/packages/rock_solid)
[![Docs](https://img.shields.io/badge/documentation-gray.svg)](https://rock-solid.hexdocs.pm)

Data generation tool from JSON schemas.

> [!IMPORTANT]
> This project is still in experimental stage. See [Known bugs and issues](#knwon-bugs-and-issues) and the [roadmap](./ROADMAP.md)


## Usage
Add to your list of dependencies
```elixir
def deps do
  [
    {:rock_solid, "~> 0.0.10", only: :test}
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

or as a generator, since `RockSolid.from_schema/1` returns elements of `StreamData.t()`

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

## Overview and Architecture
This library is inspired by [hypothesis-jsonschema](https://github.com/python-jsonschema/hypothesis-jsonschema), [this paper](https://arxiv.org/abs/1911.12651) and [schemathesis](https://github.com/schemathesis/schemathesis). However, the existing libraries contain several issues and bugs, and do not support many common patterns in existing JSON Schemas found in the wild.

As described in the paper, the goal is to transform a given JSON schema such that every subschema can be used to generate random valid data. For this to happen, a valid subschema is one of:
- `anyOf` with no additional keywords
- A map with `type` + keywords applying only to its type, plus `not`
- A map with `"enum"` or `"const"` and no extra keywords
- `$ref` to a valid subschema
- `true`

Given that JSON schema supports more keywords that cannot be used to generate data, the schema must be transformed accordingly.

The entire process consists of three main steps: Migration, Transformation, Generation

### Migration
The input schema, and all the remote schemas referenced are transformed to `draft-2020-12` compliant schemas. Additionally, `$ref` to `$anchor` are replaced by the JSON pointer instead, and all `$ref` to paths that have been modified are updated accordingly. All relative pointers are replaced by their absolute value so that they can be fetched and referenced unambiguously from any schema. The schemas are then saved in local cache directory and in process memory.

### Transformation
The migrated input schema is recursively transformed into a subschema valid for generation by expanding and intersecting subschemas. Remote schemas are only transformed on-demand, and the transformed result is stored in process memory.

### Generation
The transformed schema is used to generate valid data using `StreamData` and `MoreStreamData` libraries.


## Knwon bugs and issues

Ordered by most common to least common based on testing schemas from [Schemastore](https://github.com/SchemaStore/schemastore)

### Too many elements filtered out
When reaching the data generation step, `StreamData` throws an error because too many elements have been filtered out. This happens mostly for `"string"` type when `pattern` or `format` are specified, along with `maxLength` and/or `minLength`. Since the underlying `from_regex` and `from_format` lack options to set min/max length, we first have to generate the string and then filter them. The solution requires generating from regex or from format that are length-aware.

Another case are schemas containing a `not` clause that overlaps with most elements generated. Aside from implementing a smarter `not` intersection there is not much to do.

### Timeout
Usually due to heavy recursive definitions where the recursive schemas also contain many fields and options to generate from. One possible solution is to peek at the next value, if it is a `$ref` then geenrate with "less chance" if it's a property, or if it's an array of `$ref` scale down the generation size even further.

### Recursive intersection
In order to perform intersection of recurisve schemas, we create a placeholder, and when we reach it again we return it and create a new schema on demand. The problem is that sometimes recursive schemas are reached from different branches, the code tries to return the placeholder but it doesn't exist yet because we are in the process of creating it.

### "$dynamicRef" and "$dynamicAnchor"
Unsupported, might be supported in the future

### "unevaluatedItems" and "unevaluatedProperties"
Unsupported when not `false`, and not planning to support it.

### "contains" keyword
The contains keyword is transformed by adding a `prefixItem` or intersecting with the first `prefixItem` that matches the `contains` condition. Additionally, `maxContains` is not supported. This current implementation is a quick workaround and causes failures. It must be rewritten.

### dependentSchemas and oneOf
Both keywords can often cause timeouts if the number of elements is too large:
- For `dependentSchemas` we compute the power set of all the keys and then calculate each intersection. This is fine when there are few `dependentSchemas` but the number grows exponentially, the number of combinations is `2**length`, meaning that for 8 keys there will be 256 schemas. There is no current solution or alternative to this.
- For `oneOf`, since it behaves as a XOR, we have to intersect each clause with the negation of the rest. Prefer `anyOf` instead which performs a single-pass intersection between all the schemas.
