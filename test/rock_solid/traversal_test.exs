defmodule RockSolid.TraversalTest do
  use ExUnit.Case

  alias RockSolid.Schemas.Vocabulary
  alias RockSolid.Traversal

  doctest RockSolid.Traversal

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
end
