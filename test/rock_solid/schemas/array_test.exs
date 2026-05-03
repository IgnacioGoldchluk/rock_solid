defmodule RockSolid.Schemas.ArrayTest do
  use RockSolid.TestCase, async: true

  alias RockSolid.Context
  alias RockSolid.Schemas.Array

  describe "new/1" do
    test "uniqueItems with enum sets maxItems" do
      schema = %{"items" => %{"enum" => ["1.0", "1.2", "1.3"]}, "uniqueItems" => true}

      assert {:ok, parsed} = Array.new(schema)
      assert parsed["maxItems"] == 3
    end

    test "uniqueItems with $ref as enum sets maxItems" do
      schema_id = schema_id()

      Context.put_schema(%{
        "$id" => schema_id,
        "$defs" => %{"names" => %{"enum" => ["Alice", "Bob"]}}
      })

      schema = %{"items" => %{"$ref" => "#{schema_id}#/$defs/names"}, "uniqueItems" => true}

      assert {:ok, parsed} = Array.new(schema)
      assert parsed["maxItems"] == 2
    end

    test "minContains and maxContains without contains are ignored" do
      assert {:ok, schema} = Array.new(%{"items" => %{"type" => "integer"}})

      refute Map.has_key?(schema, "minContains")
      refute Map.has_key?(schema, "maxContains")
    end

    test "items=false and no prefixItems returns empty array" do
      assert {:ok, %{"enum" => [[]]}} == Array.new(%{"items" => false})
    end

    test "items=false, no prefixItems and minItems > 0 returns error" do
      assert {:error, "empty array"} == Array.new(%{"items" => false, "minItems" => 1})
    end

    test "items=false with prefixItems is valid" do
      assert {:ok, _} =
               Array.new(%{"items" => false, "prefixItems" => [%{"type" => "number"}]})
    end

    test "minItems > maxItems is invalid" do
      assert {:error, [%Zoi.Error{message: msg}]} = Array.new(%{"minItems" => 2, "maxItems" => 1})
      assert msg == "minItems > maxItems"
    end

    test "contains with minContains > maxContains is invalid" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Array.new(%{
                 "contains" => %{"type" => "string"},
                 "minContains" => 5,
                 "maxContains" => 3
               })

      assert msg == "minContains > maxContains"
    end

    test "minContains > maxItems is invalid" do
      assert {:error, [%Zoi.Error{message: msg}]} =
               Array.new(%{
                 "contains" => %{"type" => "string"},
                 "minContains" => 10,
                 "maxItems" => 8
               })

      assert msg == "minContains > maxItems"
    end

    test "prefixItems longer than maxItems trims" do
      assert {:ok, schema} =
               Array.new(%{
                 "prefixItems" => List.duplicate(%{"type" => "string"}, 5),
                 "maxItems" => 3
               })

      assert schema["prefixItems"] == List.duplicate(%{"type" => "string"}, 3)
      assert schema["items"] == false
    end
  end
end
