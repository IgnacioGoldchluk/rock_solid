[![CI](https://github.com/IgnacioGoldchluk/rock_solid/actions/workflows/ci.yaml/badge.svg)](https://github.com/IgnacioGoldchluk/rock_solid/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/rock_solid)](https://github.com/IgnacioGoldchluk/rock_solid/blob/main/LICENSE.md)
[![Version](https://img.shields.io/hexpm/v/rock_solid.svg)](https://hex.pm/packages/rock_solid)
[![Docs](https://img.shields.io/badge/documentation-gray.svg)](https://rock-solid.hexdocs.pm)

# RockSolid

RockSolid is an Elixir library that turns a JSON Schema into a `StreamData` generator.

Use it when you want property tests, examples, fixtures, or sample payloads that follow the same JSON Schema used by your API, configuration file, event, or document format. Supports JSON Schema draft 04 through draft 2020-12 and exposes one main API: `RockSolid.from_schema/2`.

## When to Use RockSolid

RockSolid is useful when you already have a JSON Schema and want generated data instead of hand-written fixtures.

Common use cases:

- Generate input data inside `ExUnitProperties` property tests.
- Produce JSON-compatible maps, lists, strings, numbers, booleans, and `nil` values from schema definitions.
- Check that code paths accept a wider range of valid payloads than a small
  fixture set would cover.
- Generate realistic samples for schemas that use constraints such as `required`, `properties`, `items`, `enum`, `const`, `pattern`, `format`, `minimum`, `maximum`, `oneOf`, `anyOf`, `allOf`, and `not`.

RockSolid is not a JSON Schema validator. It generates values that should match the schema. Use a validator when you need to check external input.

## Install

Add `rock_solid` to your dependencies:

```elixir
def deps do
  [
    {:rock_solid, "~> 0.0.12", only: :test}
  ]
end
```

## Usage

Starting from a JSON Schema represented as a map with string keys

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

`RockSolid.from_schema/2` returns a `StreamData.t()`, so the result can be used anywhere a StreamData generator is accepted.

## Sample values

You can also use RockSolid directly take a few sample values from a schema.

```elixir
iex> schema = %{
   "type" => "object",
   "properties" => %{
     "serverIPs" => %{
       "type" => "array",
       "items" => %{"type" => "string", "format" => "ipv4"},
       "uniqueItems" => true,
       "minItems" => 1
     },
     "serverName" => %{
       "type" => "string",
       "pattern" => "^[a-z][a-z_0-9]{2,255}$"
     }
   },
   "required" => ["serverIPs", "serverName"],
   "additionalProperties" => false
 }

iex> schema |> RockSolid.from_schema() |> Enum.take(3)
[
  %{"serverIPs" => ["148.50.92.205"], "serverName" => "a5l"},
  %{"serverIPs" => ["230.26.166.121"], "serverName" => "y_w"},
  %{
    "serverIPs" => ["144.154.111.248", "155.134.134.38"],
    "serverName" => "v2_5"
  }
]
```

## How Generation Works

RockSolid simplifies and migrates supported JSON Schema drafts into an internal format, resolves schema references through the configured resolver, and builds a generator that tries to emit only values accepted by the schema.

The more precise the schema is, the easier it is for RockSolid to generate useful values quickly. In practice, schemas that specify `"type"`, keep branching logic simple, avoid very narrow negative constraints, and restrict unexpected object keys with `"additionalProperties": false` are easier to generate from.

See [guides/recommendations.md](guides/recommendations.md) for schema-writing
recommendations that improve generation quality and performance.

## Known Limitations

RockSolid can generate valid payloads for most schemas, with an 87% passing
rate when tested against the SchemaStore catalog. The main known limitations
are:

- Very narrow value spaces can fail to generate even when valid values exist.
  This is common with combinations of `"pattern"` and `minLength`/`maxLength`,
  or with broad `"not"` clauses. Prefer encoding string length directly in the
  regex pattern, and keep `"not"` clauses specific.
- Complex branching can time out, especially with repeated
  `"if"`/`"then"`/`"else"`, `"dependentSchemas"`, and `"oneOf"`. Prefer
  `"anyOf"` when it expresses the same intent.
- Recursive schemas are supported, but intersections between recursive schemas
  and other subschemas can still fail.
- `"$dynamicRef"`, `"$dynamicAnchor"`, `"unevaluatedItems"`,
  `"unevaluatedProperties"`, and `"maxContains"` are not currently supported
  because their behavior is defined at runtime.
