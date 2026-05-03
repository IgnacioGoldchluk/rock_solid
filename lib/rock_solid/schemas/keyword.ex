defmodule RockSolid.Schemas.Keyword do
  @moduledoc false

  def all do
    booleans() ++ type_agnostic() ++ object() ++ array() ++ string() ++ number()
  end

  def booleans, do: ["not", "oneOf", "anyOf", "allOf"]

  def type_agnostic, do: ["type", "format", "if", "then", "else", "const", "enum"]

  def object do
    [
      "required",
      "properties",
      "patternProperties",
      "additionalProperties",
      "dependentRequired",
      "dependentSchemas",
      "maxProperties",
      "minProperties",
      "unevaluatedProperties"
    ]
  end

  def array do
    [
      "contains",
      "items",
      "maxContains",
      "minContains",
      "maxItems",
      "minItems",
      "prefixItems",
      "uniqueItems",
      "unevaluatedItems"
    ]
  end

  def string do
    [
      "contentMediaType",
      "contentEncoding",
      "contentSchema",
      "maxLength",
      "minLength",
      "pattern"
    ]
  end

  def number do
    [
      "minimum",
      "maximum",
      "exclusiveMinimum",
      "exclusiveMaximum",
      "format",
      "multipleOf"
    ]
  end
end
