defmodule RockSolid.Intersection.ArrayTest do
  use ExUnit.Case, async: true

  alias RockSolid.Intersection

  describe "intersection/1" do
    test "no matching items is invalid" do
      s1 = %{"type" => "array", "items" => %{"type" => "string"}}
      s2 = %{"type" => "array", "items" => %{"type" => "number"}}

      assert {:error, _} = Intersection.intersection(s1, s2)
    end

    test "matching items" do
      s1 = %{"type" => "array", "items" => %{"type" => "number"}}
      s2 = %{"type" => "array", "items" => %{"type" => "integer", "minimum" => 0}}

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{"type" => "array", "items" => %{"type" => "integer", "minimum" => 0}}
    end

    test "no matching prefixItems returns empty array" do
      s1 = %{"type" => "array", "prefixItems" => [%{"type" => "number"}]}
      s2 = %{"type" => "array", "prefixItems" => [%{"type" => "string"}]}

      assert {:ok, %{"enum" => [[]]}} == Intersection.intersection(s1, s2)
    end

    test "no matching prefixItems with minItems returns error" do
      s1 = %{"type" => "array", "prefixItems" => [%{"type" => "number"}], "minItems" => 1}
      s2 = %{"type" => "array", "prefixItems" => [%{"type" => "string"}]}

      assert {:error, _} = Intersection.intersection(s1, s2)
    end

    test "partial prefixItems match" do
      s1 = %{"type" => "array", "prefixItems" => [%{"type" => "number"}, %{"type" => "string"}]}

      s2 = %{
        "type" => "array",
        "prefixItems" => [%{"type" => "number"}, %{"type" => "boolean"}, %{"type" => "string"}]
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "type" => "array",
               "items" => false,
               "prefixItems" => [%{"type" => "number"}],
               "maxItems" => 1
             }
    end

    test "all prefixItems match but no items match" do
      s1 = %{"type" => "array", "prefixItems" => [%{"type" => "number"}, %{"type" => "number"}]}

      s2 = %{
        "type" => "array",
        "prefixItems" => [%{"type" => "number"}],
        "items" => %{"type" => "string"}
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "type" => "array",
               "items" => false,
               "prefixItems" => [%{"type" => "number"}],
               "maxItems" => 1
             }
    end

    test "prefixItems match and items match" do
      s1 = %{
        "type" => "array",
        "prefixItems" => [%{"type" => "string"}, %{"type" => "string"}],
        "items" => %{"type" => "string", "maxLength" => 20}
      }

      s2 = %{
        "type" => "array",
        "prefixItems" => [%{"type" => "string"}],
        "items" => %{"type" => "string", "minLength" => 6}
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "type" => "array",
               "items" => %{"type" => "string", "minLength" => 6, "maxLength" => 20},
               "prefixItems" => [%{"type" => "string"}, %{"type" => "string", "minLength" => 6}]
             }
    end

    test "prefixItems match and items match other prefixItems" do
      s1 = %{
        "type" => "array",
        "prefixItems" => [%{"type" => "string"}, %{"type" => "string"}],
        "items" => false
      }

      s2 = %{
        "type" => "array",
        "prefixItems" => [%{"type" => "string"}],
        "items" => %{"type" => "string", "minLength" => 6}
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "type" => "array",
               "items" => false,
               "prefixItems" => [%{"type" => "string"}, %{"type" => "string", "minLength" => 6}],
               "maxItems" => 2
             }
    end

    test "contains in one schema cannot match the other one" do
      s1 = %{
        "type" => "array",
        "items" => %{"type" => "string", "maxLength" => 10},
        "contains" => %{"const" => "ENV"}
      }

      s2 = %{"type" => "array", "items" => %{"type" => "string", "minLength" => 4}}
      assert {:error, "no match for contains" <> _} = Intersection.intersection(s1, s2)
    end

    test "contains matches a prefixItem" do
      s1 = %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "contains" => %{"const" => "ENV"}
      }

      s2 = %{
        "type" => "array",
        "items" => %{"type" => "number"},
        "prefixItems" => [%{"type" => "string", "maxLength" => 8}]
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "items" => false,
               "prefixItems" => [%{"enum" => ["ENV"]}],
               "type" => "array",
               "maxItems" => 1
             }
    end

    test "both contains match prefix items" do
      s1 = %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "prefixItems" => [%{"type" => "number"}, %{"type" => "number"}],
        "contains" => %{"const" => 123}
      }

      s2 = %{
        "type" => "array",
        "contains" => %{"const" => 456},
        "items" => %{"type" => "string"},
        "prefixItems" => [%{"type" => "number"}, %{"type" => "number"}]
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "items" => %{"type" => "string"},
               "prefixItems" => [%{"enum" => [123]}, %{"enum" => [456]}],
               "type" => "array"
             }
    end

    test "at least one 'uniqueItems' sets to unique" do
      s1 = %{"type" => "array", "items" => %{"type" => "number"}}

      s2 = %{
        "type" => "array",
        "items" => %{"anyOf" => [%{"type" => "integer"}, %{"type" => "string"}]},
        "uniqueItems" => true
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "type" => "array",
               "items" => %{"type" => "integer"},
               "uniqueItems" => true
             }
    end

    test "appends to prefixItems" do
      s1 = %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "prefixItems" => [
          %{"type" => "string", "maxLength" => 3},
          %{"type" => "string", "maxLength" => 3}
        ],
        "contains" => %{"const" => "mycontains1"}
      }

      s2 = %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "prefixItems" => [
          %{"type" => "string", "maxLength" => 3},
          %{"type" => "string", "maxLength" => 3}
        ],
        "contains" => %{"const" => "mycontains2"}
      }

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "contains" => %{
                 "anyOf" => [%{"enum" => ["mycontains2"]}, %{"enum" => ["mycontains1"]}]
               },
               "items" => %{"type" => "string"},
               "prefixItems" => [
                 %{"maxLength" => 3, "type" => "string"},
                 %{"maxLength" => 3, "type" => "string"},
                 %{"enum" => ["mycontains1"]},
                 %{"enum" => ["mycontains2"]}
               ],
               "type" => "array"
             }
    end

    test "contains in one schema matches the other one" do
      s1 = %{
        "type" => "array",
        "items" => %{"type" => "string", "maxLength" => 10},
        "contains" => %{"const" => "ENV"}
      }

      s2 = %{"type" => "array", "items" => %{"type" => "string", "pattern" => "^ENV"}}

      assert {:ok, schema} = Intersection.intersection(s1, s2)

      assert schema == %{
               "contains" => %{"enum" => ["ENV"]},
               "items" => %{"maxLength" => 10, "pattern" => "^ENV", "type" => "string"},
               "prefixItems" => [%{"enum" => ["ENV"]}],
               "type" => "array"
             }
    end
  end
end
