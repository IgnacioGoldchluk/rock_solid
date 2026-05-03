defmodule RockSolid.IntersectionTest do
  use RockSolid.TestCase, async: true

  alias RockSolid.Intersection

  describe "intersection/2" do
    test "intersection of same ref returns itself" do
      schema = %{"$ref" => "#/$defs/user"}

      assert {:ok, %{"$ref" => "#/$defs/user"}} == Intersection.intersection(schema, schema)
    end

    test "intersection of true and schema returns schema" do
      schema = %{"type" => "number", "minimum" => 2}

      assert {:ok, schema} == Intersection.intersection(schema, true)
      assert {:ok, schema} == Intersection.intersection(true, schema)
    end

    test "intersection of false and schema returns false" do
      schema = %{"type" => "number", "minimum" => 2}

      assert {:ok, false} == Intersection.intersection(schema, false)
      assert {:ok, false} == Intersection.intersection(false, schema)
    end

    test "intersection of boolean returns boolean" do
      schema = %{"type" => "boolean"}
      assert {:ok, schema} == Intersection.intersection(schema, schema)
    end

    test "intersection of null returns null" do
      schema = %{"type" => "null"}
      assert {:ok, schema} == Intersection.intersection(schema, schema)
    end
  end

  describe "impossible?/1" do
    test "impossible const returns true" do
      schema = %{
        "const" => [1, 2],
        "not" => %{"type" => "array", "items" => %{"type" => "number"}}
      }

      assert Intersection.impossible?(schema)
    end

    test "impossible enums returns true" do
      schema = %{"enum" => [1, 2], "not" => %{"type" => "integer"}}
      assert Intersection.impossible?(schema)
    end
  end

  describe "intersection of anyOf" do
    test "multiple overlapping anyOf returns anyOf" do
      s1 = %{"anyOf" => [%{"type" => "number"}, %{"type" => "string"}, %{"type" => "boolean"}]}
      s2 = %{"anyOf" => [%{"type" => "string"}, %{"type" => "integer"}, %{"type" => "array"}]}

      assert {:ok, %{"anyOf" => results}} = Intersection.intersection(s1, s2)
      assert length(results) == 2
      assert %{"type" => "integer"} in results
      assert %{"type" => "string"} in results
    end

    test "single overlapping value returns one result" do
      s1 = %{"anyOf" => [%{"type" => "string"}, %{"type" => "number"}]}
      s2 = %{"anyOf" => [%{"type" => "array"}, %{"type" => "string"}]}

      assert {:ok, result} = Intersection.intersection(s1, s2)
      assert result == %{"type" => "string"}
    end

    test "anyOf vs single schema with multiple overlapping cases" do
      s1 = %{"anyOf" => [%{"multipleOf" => 2}, %{"multipleOf" => 3, "type" => "integer"}]}
      s2 = %{"type" => "number"}

      assert {:ok, %{"anyOf" => result}} = Intersection.intersection(s1, s2)
      assert length(result) == 2
      assert %{"type" => "number", "multipleOf" => 2} in result
      assert %{"type" => "integer", "multipleOf" => 3} in result
    end

    test "anyOf with 'not' clause includes it" do
      s1 = %{"anyOf" => [%{"multipleOf" => 5}, %{"minimum" => 0}, %{"multipleOf" => 4}]}
      s2 = %{"type" => "integer", "not" => %{"multipleOf" => 2}}
      assert {:ok, result} = Intersection.intersection(s1, s2)

      assert result == %{
               "anyOf" => [
                 %{"multipleOf" => 5, "type" => "integer", "not" => %{"multipleOf" => 2}},
                 %{"minimum" => 0, "type" => "integer", "not" => %{"multipleOf" => 2}}
               ]
             }
    end

    test "anyOf with enum returns the enums" do
      s1 = %{"enum" => [3, 9], "type" => "number"}

      s2 = %{
        "anyOf" => [
          %{"type" => "array"},
          %{"type" => "boolean"},
          %{"type" => "null"},
          %{"type" => "number"},
          %{"type" => "object"},
          %{"type" => "string"}
        ]
      }

      assert {:ok, %{"enum" => [3, 9]}} == Intersection.intersection(s1, s2)
      assert {:ok, %{"enum" => [3, 9]}} == Intersection.intersection(s2, s1)
    end

    test "impossible not returns error" do
      s1 = %{"type" => "integer", "minimum" => 100}
      s2 = %{"minLength" => 10, "not" => %{"type" => "number"}}

      assert {:error, "empty intersection with 'not' clauses" <> _} =
               Intersection.intersection(s1, s2)
    end
  end
end
