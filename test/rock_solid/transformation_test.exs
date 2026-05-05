defmodule RockSolid.TransformationTest do
  use RockSolid.TestCase, async: true

  alias RockSolid.Context
  alias RockSolid.Transformation

  describe "to_any_of/1" do
    test "empty dict returns everything" do
      %{"anyOf" => result} = Transformation.to_any_of(%{})

      expected = [
        %{"type" => "array"},
        %{"type" => "boolean"},
        %{"type" => "null"},
        %{"type" => "number"},
        %{"type" => "object"},
        %{"type" => "string"}
      ]

      assert equals?(result, expected)
    end

    test "booleans are returned as is" do
      assert true == Transformation.to_any_of(true)
      assert false == Transformation.to_any_of(false)
    end

    test "specified single type" do
      schema = %{"type" => "integer", "maxLength" => 2, "minimum" => 5}
      assert %{"type" => "integer", "minimum" => 5} == Transformation.to_any_of(schema)
    end

    test "multiple types specified" do
      schema = %{"type" => ["number", "string"]}
      assert %{"anyOf" => results} = Transformation.to_any_of(schema)

      assert length(results) == 2
      assert %{"type" => "number"} in results
      assert %{"type" => "string"} in results
    end

    test "ignores invalid format" do
      schema = %{"$id" => "https://example.com/schema", "format" => "invalid"}

      %{"anyOf" => result} = Transformation.to_any_of(schema)

      expected = [
        %{"$id" => "https://example.com/schema", "type" => "array"},
        %{"$id" => "https://example.com/schema", "type" => "boolean"},
        %{"$id" => "https://example.com/schema", "type" => "null"},
        %{"$id" => "https://example.com/schema", "type" => "number"},
        %{"$id" => "https://example.com/schema", "type" => "object"},
        %{"$id" => "https://example.com/schema", "type" => "string"}
      ]

      assert equals?(result, expected)
    end

    test "existing format is added to type" do
      schema = %{"format" => "ipv4"}

      %{"anyOf" => result} = Transformation.to_any_of(schema)

      expected = [
        %{"type" => "array"},
        %{"type" => "boolean"},
        %{"type" => "null"},
        %{"type" => "number"},
        %{"type" => "object"},
        %{"format" => "ipv4", "type" => "string"}
      ]

      assert equals?(result, expected)
    end

    test "consts convert to expected type" do
      assert %{"type" => "boolean", "const" => true} ==
               Transformation.to_any_of(%{"const" => true})

      assert %{"type" => "null", "const" => nil} == Transformation.to_any_of(%{"const" => nil})

      assert %{"type" => "string", "const" => "hi"} ==
               Transformation.to_any_of(%{"const" => "hi"})

      assert %{"type" => "array", "const" => [1, 2]} ==
               Transformation.to_any_of(%{"const" => [1, 2]})

      assert %{"type" => "number", "const" => 1} == Transformation.to_any_of(%{"const" => 1})

      assert %{"type" => "object", "const" => %{"name" => "Alice"}} ==
               Transformation.to_any_of(%{"const" => %{"name" => "Alice"}})
    end

    test "number and integer then number takes priority" do
      schema = %{"type" => ["number", "integer"]}
      assert %{"type" => "number"} == Transformation.to_any_of(schema)
    end

    test "string and integer are converted to anyOf" do
      schema = %{"type" => ["string", "integer"]}

      assert %{"anyOf" => [%{"type" => "integer"}, %{"type" => "string"}]} ==
               Transformation.to_any_of(schema)
    end

    test "multiple types but const takes priority" do
      schema = %{"type" => ["array", "string"], "const" => "hello"}
      assert %{"type" => "string", "const" => "hello"} == Transformation.to_any_of(schema)
    end

    test "unspecified types keeps everything" do
      schema = %{"multipleOf" => 2, "minLength" => 3, "minimum" => 0}

      %{"anyOf" => results} = Transformation.to_any_of(schema)

      expected = [
        %{"type" => "array"},
        %{"type" => "boolean"},
        %{"type" => "null"},
        %{"multipleOf" => 2, "type" => "number", "minimum" => 0},
        %{"type" => "object"},
        %{"minLength" => 3, "type" => "string"}
      ]

      assert equals?(results, expected)
    end

    test "enums splits by type" do
      schema = %{"enum" => [1, "2", 3, false, nil]}

      %{"anyOf" => result} = Transformation.to_any_of(schema)

      assert length(result) == 4
      assert %{"type" => "number", "enum" => [1, 3]} in result
      assert %{"type" => "null", "enum" => [nil]} in result
      assert %{"type" => "string", "enum" => ["2"]} in result
      assert %{"type" => "boolean", "enum" => [false]} in result
    end
  end

  describe "all_of_to_any_of/1" do
    test "true returns all schemas" do
      assert {:ok, %{"anyOf" => results}} = Transformation.all_of_to_any_of([true])

      expected = [
        %{"type" => "array"},
        %{"type" => "boolean"},
        %{"type" => "null"},
        %{"type" => "number"},
        %{"type" => "object"},
        %{"type" => "string"}
      ]

      assert equals?(results, expected)
    end

    test "returns error when no type matches" do
      all_of = [
        %{"type" => "number"},
        %{"type" => "string"},
        %{"items" => %{"type" => "string"}}
      ]

      assert {:error, "empty anyOf"} == Transformation.all_of_to_any_of(all_of)
    end

    test "returns error for matching type but no overlap" do
      all_of = [
        %{"type" => "number"},
        %{"minimum" => 10},
        %{"maximum" => 5}
      ]

      assert {:error, "empty anyOf"} == Transformation.all_of_to_any_of(all_of)
    end

    test "returns single value when only one type matches" do
      all_of = [
        %{"type" => "integer"},
        %{"minimum" => 10},
        %{"minimum" => 30},
        %{"maximum" => 100},
        %{"multipleOf" => 3},
        %{"multipleOf" => 2}
      ]

      assert {:ok, schema} = Transformation.all_of_to_any_of(all_of)

      assert schema == %{
               "type" => "integer",
               "minimum" => 30,
               "maximum" => 100,
               "multipleOf" => 6
             }
    end

    test "returns matching enums/const" do
      all_of = [%{"enum" => [1, 2, "a", 6]}, %{"minimum" => 4}]
      assert {:ok, %{"enum" => ["a", 6]}} == Transformation.all_of_to_any_of(all_of)

      all_of = [%{"const" => 0.25}, %{"type" => "number"}]
      assert {:ok, %{"enum" => [0.25]}} == Transformation.all_of_to_any_of(all_of)

      all_of = [%{"enum" => [0.25, "0.25"]}, %{"type" => ["number", "string"]}]
      assert {:ok, %{"enum" => [0.25, "0.25"]}} == Transformation.all_of_to_any_of(all_of)
    end

    test "returns error for no matching enum/const" do
      all_of = [%{"enum" => ["Alice", "Bob"]}, %{"type" => "array"}]
      assert {:error, "no enum in " <> _} = Transformation.all_of_to_any_of(all_of)

      all_of = [%{"const" => "Alice"}, %{"minLength" => 2}, %{"maxLength" => 4}]
      assert {:error, "no enum in " <> _} = Transformation.all_of_to_any_of(all_of)
    end

    test "returns anyOf for multiple matching types" do
      all_of = [%{"type" => ["number", "string"]}, %{"minimum" => 0}, %{"pattern" => "\d+"}]
      assert {:ok, %{"anyOf" => result}} = Transformation.all_of_to_any_of(all_of)

      assert %{"type" => "string", "pattern" => "\d+"} in result
      assert %{"type" => "number", "minimum" => 0} in result

      assert length(result) == 2
    end
  end

  describe "one_of_to_any_of/1" do
    test "single schema returns itself" do
      schema = %{"type" => "object", "required" => ["foo"]}
      assert {:ok, schema} == Transformation.one_of_to_any_of([schema])
    end

    test "non-ovelapping schemas are returned without changes" do
      schemas = [%{"type" => "number", "minimum" => 0}, %{"type" => "integer", "maximum" => -1}]

      assert {:ok, %{"anyOf" => results}} = Transformation.one_of_to_any_of(schemas)
      assert equals?(results, schemas)
    end

    test "multiple overlapping clauses" do
      schemas = [
        %{"type" => "number", "multipleOf" => 2},
        %{"type" => "number", "multipleOf" => 3},
        %{"type" => "number", "maximum" => 0}
      ]

      assert {:ok, %{"anyOf" => results}} = Transformation.one_of_to_any_of(schemas)

      expected = [
        %{
          "multipleOf" => 2,
          "not" => %{
            "anyOf" => [
              %{"multipleOf" => 6, "type" => "number"},
              %{"maximum" => 0, "type" => "number", "multipleOf" => 2}
            ]
          },
          "type" => "number"
        },
        %{
          "multipleOf" => 3,
          "not" => %{
            "anyOf" => [
              %{"multipleOf" => 6, "type" => "number"},
              %{"maximum" => 0, "type" => "number", "multipleOf" => 3}
            ]
          },
          "type" => "number"
        },
        %{
          "maximum" => 0,
          "not" => %{
            "anyOf" => [
              %{"multipleOf" => 2, "type" => "number", "maximum" => 0},
              %{"multipleOf" => 3, "type" => "number", "maximum" => 0}
            ]
          },
          "type" => "number"
        }
      ]

      assert equals?(results, expected)
    end

    test "impossible clause is discarded" do
      schemas = [%{"type" => "number"}, %{"type" => "integer"}]

      assert {:ok, result} = Transformation.one_of_to_any_of(schemas)
      assert result == %{"type" => "number", "not" => %{"type" => "integer"}}
    end

    test "negates const" do
      schemas = [%{"type" => "boolean"}, %{"const" => true}]

      assert {:ok, %{"type" => "boolean", "not" => %{"enum" => [true]}}} ==
               Transformation.one_of_to_any_of(schemas)
    end

    test "impossible XOR returns error" do
      schemas = [%{"type" => "number"}, %{"type" => "number"}]
      assert {:error, "impossible oneOf condition"} == Transformation.one_of_to_any_of(schemas)
    end

    test "multiple not clauses accumulate" do
      schemas = [
        %{"minimum" => 0},
        %{"multipleOf" => 2, "type" => "number"},
        %{"multipleOf" => 4, "type" => "number"},
        %{"multipleOf" => 8, "type" => "number"}
      ]

      assert {:ok, %{"anyOf" => results}} = Transformation.one_of_to_any_of(schemas)

      expected = [
        %{"minimum" => 0, "not" => %{"minimum" => 0, "multipleOf" => 2, "type" => "number"}},
        %{
          "multipleOf" => 2,
          "not" => %{
            "anyOf" => [
              %{"minimum" => 0, "multipleOf" => 2, "type" => "number"},
              %{"multipleOf" => 4, "type" => "number"}
            ]
          },
          "type" => "number"
        }
      ]

      assert equals?(results, expected)
    end

    test "overlapping clauses adds a not" do
      schemas = [
        %{"type" => "number", "multipleOf" => 2},
        %{"type" => "number", "multipleOf" => 3}
      ]

      assert {:ok, %{"anyOf" => results}} = Transformation.one_of_to_any_of(schemas)

      assert length(results) == 2

      assert %{
               "type" => "number",
               "multipleOf" => 2,
               "not" => %{"multipleOf" => 6, "type" => "number"}
             } in results

      assert %{
               "type" => "number",
               "multipleOf" => 3,
               "not" => %{"multipleOf" => 6, "type" => "number"}
             } in results
    end
  end

  describe "expand_if_then_else/1" do
    test "schema with no if/then/else clauses is returned as is" do
      schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
      assert [schema] == Transformation.expand_if_then_else(schema)
    end

    test "schema with no else clause and valid if clause" do
      schema = %{
        "type" => "number",
        "if" => %{"multipleOf" => 2},
        "then" => %{"minimum" => 10}
      }

      results = Transformation.expand_if_then_else(schema)

      assert length(results) == 2
      assert %{"type" => "number", "not" => %{"multipleOf" => 2}} in results
      assert %{"type" => "number", "multipleOf" => 2, "minimum" => 10} in results
    end

    test "schema with else clause performs intersection in negative if case" do
      schema = %{
        "type" => "array",
        "if" => %{"minItems" => 5},
        "then" => %{"items" => %{"type" => "number"}},
        "else" => %{"prefixItems" => [%{"type" => "string"}]}
      }

      results = Transformation.expand_if_then_else(schema)

      expected = [
        %{"items" => %{"type" => "number"}, "minItems" => 5, "type" => "array"},
        %{
          "not" => %{"minItems" => 5},
          "prefixItems" => [%{"type" => "string"}],
          "type" => "array"
        }
      ]

      assert equals?(results, expected)
    end

    test "returns else clause without 'not' condition when 'if' never matches" do
      schema = %{
        "type" => "number",
        "minimum" => 0,
        "if" => %{"maximum" => -1},
        "then" => %{"multipleOf" => 2}
      }

      assert [result] = Transformation.expand_if_then_else(schema)
      assert result == %{"type" => "number", "minimum" => 0}
    end

    test "returns if/then clause intersection when 'else' clause never matches" do
      schema = %{
        "type" => "number",
        "if" => %{"minimum" => 5},
        "then" => %{"multipleOf" => 2},
        "else" => %{"type" => "array"}
      }

      assert [result] = Transformation.expand_if_then_else(schema)
      assert result == %{"type" => "number", "minimum" => 5, "multipleOf" => 2}
    end

    test "returns if/then clause intersection when 'if' always matches" do
      schema = %{
        "type" => "integer",
        "if" => %{"type" => "number"},
        "then" => %{"minimum" => 0},
        "else" => %{"maximum" => 10}
      }

      assert [result] = Transformation.expand_if_then_else(schema)
      assert result == %{"type" => "integer", "minimum" => 0}
    end
  end

  describe "merge_boolean_schemas/1" do
    test "allOf with single possible type and extra conditions" do
      schema = %{
        "$id" => schema_id(),
        "allOf" => [
          %{"type" => "object"},
          %{"required" => ["foo"]}
        ]
      }

      expected = %{
        "type" => "object",
        "required" => ["foo"],
        "properties" => %{"foo" => true}
      }

      assert expected == Transformation.simplify(schema)
    end

    test "schema without booleans returns itself" do
      schema = %{"type" => "number", "minimum" => 10}

      assert [schema] == Transformation.merge_boolean_schemas(schema)
    end

    test "empty schema returns everything" do
      result = Transformation.merge_boolean_schemas(%{})

      expected = [
        %{"type" => "array"},
        %{"type" => "boolean"},
        %{"type" => "null"},
        %{"type" => "number"},
        %{"type" => "object"},
        %{"type" => "string"}
      ]

      assert equals?(result, expected)
    end

    test "impossible intersection" do
      schema = %{
        "type" => "number",
        "minimum" => 0,
        "allOf" => [%{"type" => ["integer", "number", "string"]}, %{"maximum" => -1}],
        "anyOf" => [%{"type" => "integer"}, %{"type" => "string"}]
      }

      assert Enum.empty?(Transformation.merge_boolean_schemas(schema))
    end

    test "schema with anyOf and oneOf" do
      schema = %{
        "type" => "object",
        "oneOf" => [
          %{"type" => "object", "patternProperties" => %{".{1,20}" => %{"type" => "string"}}},
          %{"type" => "array"}
        ],
        "anyOf" => [
          %{
            "properties" => %{
              "firstName" => %{"type" => "string"},
              "lastName" => %{"type" => "string"}
            },
            "required" => ["firstName", "lastName"]
          },
          %{"properties" => %{"name" => %{"type" => "string"}}}
        ]
      }

      result = Transformation.merge_boolean_schemas(schema)

      expected = [
        %{
          "patternProperties" => %{".{1,20}" => %{"type" => "string"}},
          "properties" => %{
            "firstName" => %{"type" => "string"},
            "lastName" => %{"type" => "string"}
          },
          "required" => ["firstName", "lastName"],
          "type" => "object"
        },
        %{
          "patternProperties" => %{".{1,20}" => %{"type" => "string"}},
          "properties" => %{"name" => %{"type" => "string"}},
          "type" => "object"
        }
      ]

      assert equals?(result, expected)
    end

    test "single schema with oneOf performs intersection" do
      schema = %{
        "type" => "number",
        "not" => %{"multipleOf" => 2},
        "oneOf" => [%{"minimum" => 10}, %{"maximum" => 0}]
      }

      result = Transformation.merge_boolean_schemas(schema)

      expected = [
        %{"minimum" => 10, "not" => %{"multipleOf" => 2}, "type" => "number"},
        %{"maximum" => 0, "not" => %{"multipleOf" => 2}, "type" => "number"}
      ]

      assert equals?(result, expected)
    end
  end

  describe "expand_dependent_schemas/1" do
    test "booleans expand to themselves" do
      assert [true] == Transformation.expand_dependent_schemas(true)
      assert [false] == Transformation.expand_dependent_schemas(false)
    end

    test "schema without 'dependentSchemas' expands to itself" do
      schema = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}},
        "required" => ["name"],
        "additionalProperties" => false
      }

      assert [schema] == Transformation.expand_dependent_schemas(schema)
    end

    test "valid dependentSchema intersection" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "number"}
        },
        "required" => ["age"],
        "dependentSchemas" => %{
          "name" => %{
            "properties" => %{
              "firstName" => %{"type" => "string"},
              "lastName" => %{"type" => "string"}
            },
            "required" => ["firstName", "lastName"]
          }
        }
      }

      expected = [
        %{
          "properties" => %{"age" => %{"type" => "number"}, "name" => false},
          "required" => ["age"],
          "type" => "object"
        },
        %{
          "properties" => %{
            "age" => %{"type" => "number"},
            "firstName" => %{"type" => "string"},
            "lastName" => %{"type" => "string"},
            "name" => %{"type" => "string"}
          },
          "required" => ["age", "name", "firstName", "lastName"],
          "type" => "object"
        }
      ]

      assert equals?(expected, Transformation.expand_dependent_schemas(schema))
    end

    test "dependentSchema with anyOf" do
      schema = %{
        "type" => "object",
        "properties" => %{"foo" => %{"type" => "string"}},
        "dependentSchemas" => %{
          "foo" => %{"anyOf" => [%{"required" => ["bar"]}, %{"required" => ["baz"]}]}
        }
      }

      expected = [
        %{"properties" => %{"foo" => false}, "required" => [], "type" => "object"},
        %{
          "anyOf" => [
            %{
              "properties" => %{"bar" => true, "foo" => %{"type" => "string"}},
              "required" => ["foo", "bar"],
              "type" => "object"
            },
            %{
              "properties" => %{"baz" => true, "foo" => %{"type" => "string"}},
              "required" => ["foo", "baz"],
              "type" => "object"
            }
          ]
        }
      ]

      assert expected == Transformation.expand_dependent_schemas(schema)
    end

    test "impossible dependentSchemas are excluded" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "number", "maximum" => 100}
        },
        "required" => ["age"],
        "dependentSchemas" => %{
          "name" => %{
            "properties" => %{
              "age" => %{"type" => "number", "minimum" => 101}
            }
          }
        }
      }

      expected = [
        %{
          "properties" => %{"age" => %{"maximum" => 100, "type" => "number"}, "name" => false},
          "required" => ["age"],
          "type" => "object"
        }
      ]

      assert expected == Transformation.expand_dependent_schemas(schema)
    end
  end

  describe "expand_case_schema/1" do
    test "non-case schema is returned as is" do
      schema = %{"type" => "number", "allOf" => [%{"multipleOf" => 2}, %{"minimum" => 0}]}
      assert [schema] == Transformation.expand_case_schema(schema)
    end

    test "expands case schema" do
      schema = %{
        "type" => "object",
        "properties" => %{"country" => %{"type" => "string"}, "phone" => %{"type" => "string"}},
        "required" => ["country"],
        "allOf" => [
          %{
            "if" => %{"properties" => %{"country" => %{"const" => "USA"}}},
            "then" => %{"properties" => %{"phone" => %{"pattern" => "1.*"}}}
          },
          %{
            "if" => %{"properties" => %{"country" => %{"const" => "Russia"}}},
            "then" => %{"properties" => %{"phone" => %{"pattern" => "7.*"}}}
          }
        ]
      }

      results = Transformation.expand_case_schema(schema)

      expected = [
        %{
          "properties" => %{
            "country" => %{"enum" => ["USA"]},
            "phone" => %{"pattern" => "1.*", "type" => "string"}
          },
          "required" => ["country"],
          "type" => "object"
        },
        %{
          "properties" => %{
            "country" => %{"enum" => ["Russia"]},
            "phone" => %{"pattern" => "7.*", "type" => "string"}
          },
          "required" => ["country"],
          "type" => "object"
        },
        %{
          "properties" => %{
            "country" => %{
              "type" => "string",
              "not" => %{"anyOf" => [%{"enum" => ["USA"]}, %{"enum" => ["Russia"]}]}
            },
            "phone" => %{"type" => "string"}
          },
          "required" => ["country"],
          "type" => "object"
        }
      ]

      assert equals?(results, expected)
    end
  end

  describe "simplify_dependent_required/1" do
    test "returns same schema when dependentRequired is not present" do
      schema = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}},
        "required" => ["name"]
      }

      assert schema == Transformation.simplify_dependent_required(schema)
    end

    test "removes all dependentRequired tied to a required property" do
      schema = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}, "age" => %{"type" => "integer"}},
        "required" => ["name"],
        "dependentRequired" => %{"age" => ["name"]}
      }

      expected = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}, "age" => %{"type" => "integer"}},
        "required" => ["name"]
      }

      assert expected == Transformation.simplify_dependent_required(schema)
    end

    test "removes required property redefined in dependentRequired" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"},
          "birthDate" => %{"type" => "string", "format" => "date"},
          "country" => %{"type" => "string"}
        },
        "required" => ["name"],
        "dependentRequired" => %{"country" => ["birthDate", "age"], "name" => ["age"]}
      }

      result = Transformation.simplify_dependent_required(schema)
      assert equals?(result["required"], ["age", "name"])
      assert result["dependentRequired"] == %{"country" => ["birthDate"]}
    end

    test "does not modify non-required properties" do
      schema = %{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}, "age" => %{"type" => "integer"}},
        "dependentRequired" => %{"name" => ["age"], "age" => ["name"]}
      }

      assert schema == Transformation.simplify_dependent_required(schema)
    end

    test "graph of required properties ignores duplicates" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"},
          "birthDate" => %{"type" => "string", "format" => "date"}
        },
        "required" => ["name"],
        "dependentRequired" => %{
          "name" => ["age"],
          "age" => ["birthDate"],
          "birthDate" => ["age"]
        }
      }

      result = Transformation.simplify_dependent_required(schema)
      refute Map.has_key?(result, "dependentRequired")
    end
  end

  describe "simplify/1" do
    test "conditionally rejected property is false" do
      # We might have to do the same with `"not": true`. Decide later
      # how to handle it
      schema = %{
        "$id" => schema_id(),
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "lastName" => %{"type" => "string"}
        },
        "if" => %{"properties" => %{"name" => %{"const" => "Alice"}}},
        "then" => %{},
        "else" => %{"properties" => %{"lastName" => false}}
      }

      expected = %{
        "anyOf" => [
          %{
            "properties" => %{
              "lastName" => %{"type" => "string"},
              "name" => %{"enum" => ["Alice"]}
            },
            "type" => "object"
          },
          %{
            "not" => %{
              "properties" => %{"name" => %{"enum" => ["Alice"]}},
              "type" => "object"
            },
            "properties" => %{"lastName" => false, "name" => %{"type" => "string"}},
            "type" => "object"
          }
        ]
      }

      assert expected == Transformation.simplify(schema)
    end

    # Since we're putting the contains as prefixItems this creates an empty value. Fix later
    @tag :skip
    test "multiple mutually exclusive contains are simplified properly" do
      schema = %{
        "$id" => schema_id(),
        "type" => "array",
        "minItems" => 1,
        "allOf" => [
          %{"contains" => %{"const" => "Alice"}},
          %{"contains" => %{"const" => "Bob"}}
        ]
      }

      Transformation.simplify(schema)
    end

    # There is a bug here because we're reaching for the `#/PLACEHOLDER_${NUM}`
    # before it's inserted. Debug later how it happened
    @tag :skip
    test "recursive schema in multiple places" do
      schema = %{
        "additionalProperties" => %{
          "anyOf" => [%{"type" => "string"}, %{"$ref" => "#/$defs/foo"}],
          "minProperties" => 1
        },
        "$defs" => %{
          "foo" => %{
            "type" => "object",
            "additionalProperties" => %{
              "anyOf" => [%{"type" => "string"}, %{"$ref" => "#/$defs/foo"}]
            }
          }
        },
        "type" => "object"
      }

      Transformation.simplify(schema)
    end

    test "user-defined keywords are ignored" do
      schema = %{
        "$id" => schema_id(),
        "type" => "object",
        "x-mykey" => %{
          "properties" => "invalid",
          "additionalProperties" => "alsoInvalid"
        }
      }

      assert %{"type" => "object"} == Transformation.simplify(schema)
    end

    test "encoded properties are properly accessed" do
      schema_id = schema_id()

      schema = %{
        "$id" => schema_id,
        "type" => "object",
        "patternProperties" => %{
          "[A-Z]+" => %{"type" => "string"},
          "[a-z]+" => %{
            "allOf" => [
              %{
                # "$ref" => "#{schema_id}#/patternProperties/[A-Z]+",
                "$ref" => "#{schema_id}#/patternProperties/%5BA-Z%5D%2B",
                "x-rocksolid-refbehaviour" => "merge"
              },
              %{"type" => "string", "minLength" => 10}
            ]
          }
        }
      }

      expected = %{
        "patternProperties" => %{
          "[A-Z]+" => %{"type" => "string"},
          "[a-z]+" => %{"minLength" => 10, "type" => "string"}
        },
        "type" => "object"
      }

      assert expected == Transformation.simplify(schema)
    end

    test "if/then with property" do
      schema = %{
        "$id" => schema_id(),
        "allOf" => [
          %{
            "type" => "object",
            "if" => %{"properties" => %{"name" => %{"const" => "Alice"}}, "type" => "object"},
            "then" => %{"properties" => %{"friend" => %{"const" => "Bob"}}, "type" => "object"}
          }
        ]
      }

      expected = %{
        "anyOf" => [
          %{
            "type" => "object",
            "properties" => %{
              "name" => %{"enum" => ["Alice"]},
              "friend" => %{"enum" => ["Bob"]}
            }
          },
          %{
            "type" => "object",
            "not" => %{"type" => "object", "properties" => %{"name" => %{"enum" => ["Alice"]}}}
          }
        ]
      }

      assert expected == Transformation.simplify(schema)
    end

    test "discard 'default' and 'examples' keywords" do
      schema = %{
        "$id" => schema_id(),
        "type" => "object",
        "properties" => %{
          "asd" => %{
            "type" => "object",
            "default" => %{
              "type" => "",
              "title" => ""
            }
          }
        }
      }

      expected = %{"type" => "object", "properties" => %{"asd" => %{"type" => "object"}}}
      assert expected == Transformation.simplify(schema)
    end

    test "discard non-matching enums" do
      schema_id = schema_id()

      schema = %{
        "$id" => schema_id,
        "$defs" => %{"destination" => %{"const" => "France"}},
        "type" => "object",
        "properties" => %{
          "homeCountry" => %{
            "enum" => ["USA", "Canada", "France"],
            "not" => %{"$ref" => "#{schema_id}#/$defs/destination"}
          }
        }
      }

      expected = %{
        "properties" => %{"homeCountry" => %{"enum" => ["USA", "Canada"]}},
        "type" => "object"
      }

      assert expected == Transformation.simplify(schema)
    end

    test "simplifies objects" do
      schema = %{
        "$id" => schema_id(),
        "type" => "object",
        "properties" => %{"name" => %{"type" => ["null", "string"]}},
        "required" => ["name"],
        "if" => %{"properties" => %{"name" => %{"type" => "string"}}},
        "then" => %{
          "required" => ["lastName"],
          "properties" => %{"lastName" => %{"type" => ["null", "string"]}}
        }
      }

      expected = %{
        "anyOf" => [
          %{
            "properties" => %{
              "lastName" => %{"anyOf" => [%{"type" => "null"}, %{"type" => "string"}]},
              "name" => %{"type" => "string"}
            },
            "required" => ["name", "lastName"],
            "type" => "object"
          },
          %{
            "not" => %{
              "properties" => %{"name" => %{"type" => "string"}},
              "type" => "object"
            },
            "properties" => %{
              "name" => %{"anyOf" => [%{"type" => "null"}, %{"type" => "string"}]}
            },
            "required" => ["name"],
            "type" => "object"
          }
        ]
      }

      assert expected == Transformation.simplify(schema)
    end

    test "recursive '$ref' and regular schema intersection" do
      schema_id = schema_id()

      schema = %{
        "$id" => schema_id,
        "$defs" => %{
          "person" => %{
            "type" => "object",
            "properties" => %{
              "child" => %{
                "$ref" => "#{schema_id}#/$defs/person",
                "x-rocksolid-refbehaviour" => "merge"
              },
              "name" => %{"type" => "string"}
            }
          }
        },
        "type" => "object",
        "allOf" => [
          %{"$ref" => "#{schema_id}#/$defs/person", "x-rocksolid-refbehaviour" => "merge"},
          %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string", "minLength" => 4}
            }
          }
        ]
      }

      # Doesn't matter that we lose `$defs` in the intersection because it's still in the
      # Process dictionary
      expected = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "minLength" => 4},
          "child" => %{"$ref" => "#{schema_id}#/$defs/person"}
        }
      }

      assert expected == Transformation.simplify(schema)
    end

    test "two recursive schemas" do
      schema_id = schema_id()

      schema = %{
        "$id" => schema_id,
        "$defs" => %{
          "person" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string", "minLength" => 6},
              "children" => %{
                "type" => "array",
                "items" => %{
                  "$ref" => "#{schema_id}#/$defs/person",
                  "x-rocksolid-refbehaviour" => "merge"
                }
              }
            }
          },
          "pet" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string", "minLength" => 4},
              "children" => %{
                "type" => "array",
                "items" => %{
                  "$ref" => "#{schema_id}#/$defs/pet",
                  "x-rocksolid-refbehaviour" => "merge"
                }
              }
            }
          }
        },
        "allOf" => [
          %{"$ref" => "#{schema_id}#/$defs/person", "x-rocksolid-refbehaviour" => "merge"},
          %{"$ref" => "#{schema_id}#/$defs/pet", "x-rocksolid-refbehaviour" => "merge"}
        ]
      }

      simplified = Transformation.simplify(schema)
      placeholder_pointer = get_in(simplified, ["properties", "children", "items", "$ref"])

      placeholder_value = %{
        "properties" => %{
          "children" => %{
            "items" => %{"$ref" => placeholder_pointer},
            "type" => "array"
          },
          "name" => %{"minLength" => 6, "type" => "string"}
        },
        "type" => "object"
      }

      assert placeholder_value == Context.get_ref(placeholder_pointer)
    end

    test "raises for empty intersection" do
      schema = %{"allOf" => [%{"type" => "number"}, %{"type" => "string"}], "$id" => schema_id()}

      assert_raise RuntimeError, fn -> Transformation.simplify(schema) end
    end

    test "$ref not matching does not raise if behaviour is ignore (old draft)" do
      id = schema_id()

      schema = %{
        "$id" => id,
        "type" => "number",
        "$defs" => %{
          "foo" => %{"type" => "object"}
        },
        "$ref" => "#{id}#/$defs/foo",
        "x-rocksolid-refbehaviour" => "ignore"
      }

      assert %{"$ref" => "#{id}#/$defs/foo"} == Transformation.simplify(schema)
    end

    test "$ref matching intersects keys (new draft)" do
      id = schema_id()

      schema = %{
        "$id" => id,
        "type" => "integer",
        "$defs" => %{
          "foo" => %{"type" => "number", "maximum" => 100}
        },
        "$ref" => "#{id}#/$defs/foo",
        "minimum" => 0,
        "x-rocksolid-refbehaviour" => "merge"
      }

      expected = %{"maximum" => 100, "minimum" => 0, "type" => "integer"}

      assert expected == Transformation.simplify(schema)
    end

    test "not: true in anyOf or properties is treated as false" do
      schema = %{
        "$id" => schema_id(),
        "anyOf" => [
          %{"type" => "string"},
          %{"type" => "number"},
          %{"not" => true},
          %{"type" => "object", "properties" => %{"foo" => %{"not" => true}}}
        ]
      }

      expected = %{
        "anyOf" => [
          %{"type" => "number"},
          %{"properties" => %{"foo" => false}, "type" => "object"},
          %{"type" => "string"}
        ]
      }

      assert expected == Transformation.simplify(schema)
    end

    test "additionalPropertis are ignored if $ref already has key" do
      id = schema_id()

      schema = %{
        "$id" => id,
        "type" => "object",
        "additionalProperties" => %{"type" => "number"},
        "$defs" => %{
          "foo" => %{
            "type" => "object",
            "properties" => %{"name" => %{"type" => "string"}},
            "additionalProperties" => false
          }
        },
        "$ref" => "#{id}#/$defs/foo",
        "x-rocksolid-refbehaviour" => "merge"
      }

      expected = %{
        "additionalProperties" => false,
        "properties" => %{"name" => %{"type" => "string"}},
        "type" => "object"
      }

      assert expected == Transformation.simplify(schema)
    end

    test "additionalProperties are added if $ref does not have" do
      id = schema_id()

      schema = %{
        "$id" => id,
        "type" => "object",
        "additionalProperties" => %{"type" => "number"},
        "$defs" => %{
          "foo" => %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
        },
        "$ref" => "#{id}#/$defs/foo",
        "x-rocksolid-refbehaviour" => "merge"
      }

      expected = %{
        "additionalProperties" => %{"type" => "number"},
        "properties" => %{"name" => %{"type" => "string"}},
        "type" => "object"
      }

      assert expected == Transformation.simplify(schema)
    end

    test "$ref not matching raises (new draft)" do
      id = schema_id()

      schema = %{
        "$id" => id,
        "type" => "number",
        "$defs" => %{
          "foo" => %{"type" => "object"}
        },
        "$ref" => "#{id}#/$defs/foo",
        "x-rocksolid-refbehaviour" => "merge"
      }

      assert_raise MatchError, fn -> Transformation.simplify(schema) end
    end
  end
end
