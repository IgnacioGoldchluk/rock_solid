defmodule RockSolid.TraversalTest do
  use ExUnit.Case

  alias RockSolid.Schemas.Vocabulary
  alias RockSolid.Traversal

  doctest RockSolid.Traversal

  describe "get_in_schema/2" do
    test "raiss for invalid path" do
      schema = %{"properties" => %{"foo" => %{"type" => "string"}}}
      wrong_path = ["#", "properties", "bar"]

      assert_raise Traversal.InvalidPath, ~r/Invalid key 'bar' .*/, fn ->
        Traversal.get_in_schema(schema, wrong_path)
      end
    end
  end

  describe "property?/1" do
    test "properties and patternProperties as dependencies are not properties" do
      refute Traversal.property?(["properties", "dependencies", "#"])
      refute Traversal.property?(["patternProperties", "dependencies", "#"])
      assert Traversal.property?(["properties", "dependencies", "properties", "#"])
      assert Traversal.property?(["patternProperties", "dependencies", "properties", "#"])
    end

    test "properties is property of definition named dependencies" do
      assert Traversal.property?(["properties", "dependencies", "definitions", "#"])
    end
  end

  describe "references/1" do
    test "ignores keywords inside literals and properties" do
      schema = %{
        "$defs" => %{
          "$id" => %{"type" => "string"}
        },
        "examples" => [%{"$anchor" => "foo"}],
        "default" => %{"$ref" => "bar"}
      }

      assert Enum.empty?(Traversal.references(schema))
    end

    test "returns a map of all '$ref', '$id' and '$anchor'" do
      schema = %{
        "$defs" => %{
          "nonEmptyString" => %{
            "$anchor" => "internal-string",
            "minLength" => 1,
            "type" => "string"
          }
        },
        "$id" => "https://example.com/person",
        "$schema" => Vocabulary.draft2020_12(),
        "properties" => %{
          "firstName" => %{
            "$comment" => "As a relative reference",
            "$ref" => "#internal-string"
          },
          "lastName" => %{
            "$comment" => "As an absolute reference",
            "$ref" => "https://example.com/person#internal-string"
          }
        }
      }

      expected = %{
        "$anchor" => %{["#", "$defs", "nonEmptyString"] => "internal-string"},
        "$id" => %{["#"] => "https://example.com/person"},
        "$ref" => %{
          ["#", "properties", "firstName"] => "#internal-string",
          ["#", "properties", "lastName"] => "https://example.com/person#internal-string"
        }
      }

      assert expected == Traversal.references(schema)
    end
  end

  describe "update_in_schema/3" do
    test "update when path is list index replaces the element" do
      schema = %{
        "type" => "array",
        "items" => false,
        "prefixItems" => [%{"type" => "string"}, %{"type" => "number"}]
      }

      new_prefix_item = %{"type" => "boolean"}

      expected = %{
        "type" => "array",
        "items" => false,
        "prefixItems" => [%{"type" => "string"}, %{"type" => "boolean"}]
      }

      assert expected ==
               Traversal.update_in_schema(schema, ["#", "prefixItems", "1"], new_prefix_item)
    end
  end
end
