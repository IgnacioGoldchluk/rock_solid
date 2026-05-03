defmodule RockSolid.Intersection.NotTest do
  use ExUnit.Case

  alias RockSolid.Intersection.Not

  describe "add_clause/2" do
    test "removes const when matches properties" do
      schema = %{
        "properties" => %{
          "name" => %{"enum" => ["Alice", "Bob", "Charlie"]},
          "age" => %{"type" => "integer"}
        }
      }

      clause = %{"properties" => %{"name" => %{"const" => "Charlie"}}}

      expected = %{
        "properties" => %{
          "name" => %{"enum" => ["Alice", "Bob"]},
          "age" => %{"type" => "integer"}
        }
      }

      assert expected == Not.add_clause(schema, clause)
    end

    test "required and properties sets non-specified required to false" do
      schema = %{
        "properties" => %{
          "name" => %{"enum" => ["Alice", "Bob", "Charlie"]},
          "firstName" => %{"type" => "string"}
        }
      }

      clause = %{
        "properties" => %{"name" => %{"const" => "Alice"}},
        "required" => ["name", "firstName"]
      }

      expected = %{
        "properties" => %{
          "name" => %{"enum" => ["Bob", "Charlie"]},
          "firstName" => false
        }
      }

      assert expected == Not.add_clause(schema, clause)
    end

    test "creates unspecified properties" do
      schema = %{"type" => "object"}
      clause = %{"properties" => %{"name" => %{"const" => "Alice"}}, "required" => ["age"]}

      expected = %{
        "type" => "object",
        "properties" => %{"name" => %{"not" => %{"enum" => ["Alice"]}}, "age" => false}
      }

      assert expected == Not.add_clause(schema, clause)
    end

    test "adds 'not' clause to existing anyOf" do
      schema = %{
        "properties" => %{
          "name" => %{
            "type" => "string",
            "not" => %{"anyOf" => [%{"enum" => ["Alice"]}, %{"enum" => ["Bob"]}]}
          }
        }
      }

      clause = %{"properties" => %{"name" => %{"const" => "Charlie"}}}

      expected = %{
        "properties" => %{
          "name" => %{
            "type" => "string",
            "not" => %{
              "anyOf" => [%{"enum" => ["Charlie"]}, %{"enum" => ["Alice"]}, %{"enum" => ["Bob"]}]
            }
          }
        }
      }

      assert expected == Not.add_clause(schema, clause)
    end

    test "appends 'not' clause when property contains a not clause" do
      schema = %{
        "properties" => %{"name" => %{"type" => "string", "not" => %{"enum" => ["Alice"]}}}
      }

      clause = %{"properties" => %{"name" => %{"const" => "Bob"}}}

      expected = %{
        "properties" => %{
          "name" => %{
            "type" => "string",
            "not" => %{"anyOf" => [%{"enum" => ["Alice"]}, %{"enum" => ["Bob"]}]}
          }
        }
      }

      assert expected == Not.add_clause(schema, clause)
    end

    test "adds raw 'not' clause when property is not an enum" do
      schema = %{
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        }
      }

      clause = %{
        "required" => ["name", "age"],
        "properties" => %{"name" => %{"const" => "Alice"}, "age" => %{"const" => 22}}
      }

      expected = %{
        "properties" => %{
          "name" => %{"type" => "string", "not" => %{"enum" => ["Alice"]}},
          "age" => %{"type" => "integer", "not" => %{"enum" => [22]}}
        }
      }

      assert expected == Not.add_clause(schema, clause)
    end

    test "not clause with true property sets it to false" do
      schema = %{"properties" => %{"name" => %{"type" => "string"}}}
      clause = %{"properties" => %{"name" => true}}
      expected = %{"properties" => %{"name" => false}}

      assert expected == Not.add_clause(schema, clause)
    end

    test "doest not set property to false when it is required by the schema" do
      schema = %{
        "properties" => %{
          "name" => %{"enum" => ["Alice", "Bob", "Charlie"]},
          "firstName" => %{"type" => "string"}
        },
        "required" => ["firstName"]
      }

      clause = %{
        "properties" => %{"name" => %{"const" => "Bob"}},
        "required" => ["firstName"]
      }

      expected = %{
        "properties" => %{
          "name" => %{"enum" => ["Alice", "Charlie"]},
          "firstName" => %{"type" => "string"}
        },
        "required" => ["firstName"]
      }

      assert expected == Not.add_clause(schema, clause)
    end

    test "removes enums matching properties" do
      schema = %{
        "properties" => %{
          "name" => %{"enum" => ["Alice", "Bob", "Charlie"]},
          "age" => %{"type" => "integer"}
        }
      }

      clause = %{"properties" => %{"name" => %{"enum" => ["Alice", "Charlie"]}}}

      expected = %{
        "properties" => %{"name" => %{"enum" => ["Bob"]}, "age" => %{"type" => "integer"}}
      }

      assert expected == Not.add_clause(schema, clause)
    end

    test "removes properties included in required" do
      schema = %{
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        }
      }

      clause = %{"required" => ["age"]}

      expected = %{"properties" => %{"name" => %{"type" => "string"}, "age" => false}}

      assert expected == Not.add_clause(schema, clause)
    end

    test "adding a not clause to true returns the clause" do
      clause = %{"type" => "integer"}
      assert %{"not" => clause} == Not.add_clause(true, clause)
    end

    test "adding a 'not' clause to false returns false" do
      assert false == Not.add_clause(false, %{"type" => "object"})
    end
  end
end
