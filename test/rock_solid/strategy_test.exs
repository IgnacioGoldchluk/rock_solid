defmodule RockSolid.StrategyTest do
  use ExUnit.Case
  use ExUnitProperties

  describe "from_json_schema/1" do
    # Unskip when JSV releases new version
    @tag :skip
    property "number with decimal multipleOf saves rounding errors" do
      check_schema(%{"type" => "number", "multipleOf" => 0.1})
    end

    property "does not generate additionalProperties that match patternProperties" do
      check_schema(%{
        "patternProperties" => %{
          "^[a-zA-Z0-9_]*$" => %{
            "type" => "object",
            "additionalProperties" => false,
            "properties" => %{
              "description" => %{"type" => "string"}
            }
          }
        },
        "type" => "object"
      })
    end

    property "string with minLength and maxLength" do
      check_schema(%{"type" => "string", "minLength" => 5, "maxLength" => 6})
    end

    property "string with pattern + minLength + maxLength" do
      check_schema(%{
        "type" => "string",
        "pattern" => "^[A-Z][a-z_]+",
        "minLength" => 3,
        "maxLength" => 250
      })
    end

    property "string with format" do
      check_schema(%{
        "type" => "object",
        "properties" => %{
          "id" => %{"type" => "string", "format" => "uuid"},
          "email" => %{"type" => "string", "format" => "email"}
        },
        "required" => ["id", "email"]
      })
    end

    property "multiple properties defined with maxProperties < properties" do
      check_schema(%{
        "type" => "object",
        "maxProperties" => 1,
        "additionalProperties" => false,
        "properties" => %{
          "foo" => %{"type" => "string"},
          "bar" => %{"type" => "boolean"},
          "baz" => %{"type" => "number"}
        }
      })
    end

    property "depedentRequired as dependencies" do
      check_schema(%{
        "additionalProperties" => false,
        "dependentRequired" => %{
          "foo" => ["bar"],
          "bar" => ["baz"],
          "qux" => ["baz"]
        },
        "properties" => %{
          "foo" => %{"type" => "integer"},
          "quux" => %{"type" => "string"},
          "bar" => %{"type" => "integer"},
          "baz" => %{"format" => "uri", "type" => "string"},
          "qux" => %{"type" => "string"}
        },
        "required" => ["quux"],
        "type" => "object"
      })
    end

    property "defined properties with minProperties" do
      check_schema(%{
        "type" => "object",
        "additionalProperties" => false,
        "minProperties" => 1,
        "properties" => %{
          "foo" => %{"type" => "boolean"},
          "bar" => %{"type" => "boolean"}
        }
      })
    end

    property "catch-all patternProperties and propertyNames" do
      check_schema(%{
        "patternProperties" => %{".*" => %{"type" => ["number", "string", "boolean"]}},
        "propertyNames" => %{"pattern" => "^[A-Za-z0-9_.-]+$"},
        "type" => "object"
      })
    end

    property "additionalProperties with minProperties" do
      check_schema(%{
        "type" => "object",
        "additionalProperties" => %{"type" => "string"},
        "minProperties" => 10
      })
    end

    property "array with minItems and maxItems" do
      check_schema(%{
        "type" => "array",
        "items" => %{"type" => "string"},
        "minItems" => 1,
        "maxItems" => 2
      })
    end

    property "patternProperties with minProperties" do
      check_schema(%{
        "type" => "object",
        "additionalProperties" => false,
        "minProperties" => 10,
        "patternProperties" => %{"^[a-z]{3}$" => %{"type" => "integer"}}
      })
    end

    property "items with minItems" do
      check_schema(%{
        "type" => "array",
        "items" => %{"type" => "string", "format" => "email"},
        "minItems" => 10
      })
    end

    property "generates from basic schema" do
      check_schema(%{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "minLength" => 1},
          "age" => %{"type" => "integer", "minimum" => 0, "maximum" => 130}
        },
        "required" => ["name"]
      })
    end

    property "schema is a 'not' clause" do
      check_schema(%{"not" => %{"type" => "null"}})
    end

    property "single required" do
      check_schema(%{
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}},
        "required" => ["name"]
      })
    end

    property "numbers" do
      check_schema(%{
        "type" => "object",
        "properties" => %{
          "num1" => %{"type" => "number", "multipleOf" => 2.5},
          "num2" => %{"type" => "integer", "exclusiveMinimum" => 0},
          "num3" => %{"type" => "number", "exclusiveMaximum" => 10},
          "num4" => %{"type" => "integer", "multipleOf" => 20},
          "num5" => %{"type" => "number", "multipleOf" => 2, "minimum" => 10, "maximum" => 20}
        },
        "required" => ["num1", "num2", "num3", "num4", "num5"]
      })
    end

    property "recursive object" do
      check_schema(%{
        "$defs" => %{
          "person" => %{
            "type" => "object",
            "properties" => %{
              "parent" => %{"$ref" => "#/$defs/person"},
              "name" => %{"type" => "string", "pattern" => "^[A-Z][a-z]+$"},
              "id" => %{"type" => "integer", "minimum" => 0}
            },
            "required" => ["name", "id"],
            "additionalProperties" => false
          }
        },
        "$ref" => "#/$defs/person"
      })
    end

    property "object with propertyNames and additionalProperties" do
      check_schema(%{
        "type" => "object",
        "propertyNames" => %{
          "pattern" => "^[a-zA-Z_]+[a-zA-Z0-9_]*$"
        },
        "additionalProperties" => %{
          "anyOf" => [
            %{"type" => "boolean"},
            %{"type" => "string"},
            %{"type" => "number"}
          ]
        }
      })
    end

    property "patternProperties catches all" do
      check_schema(%{
        "type" => "object",
        "patternProperties" => %{
          "." => %{"type" => "string", "maxLength" => 6}
        }
      })
    end

    property "incompatible arrays return empty" do
      check_schema(%{
        "type" => "object",
        "required" => ["foo"],
        "properties" => %{
          "foo" => %{
            "allOf" => [
              %{"type" => "array", "prefixItems" => [%{"type" => "boolean"}]},
              %{"type" => "array", "prefixItems" => [%{"type" => "string"}]}
            ]
          }
        }
      })
    end

    property "incompatible objects returns empty" do
      check_schema(%{
        "type" => "object",
        "required" => ["foo"],
        "properties" => %{
          "foo" => %{
            "allOf" => [
              %{
                "type" => "object",
                "properties" => %{"baz" => %{"type" => "number"}},
                "additionalProperties" => false
              },
              %{
                "type" => "object",
                "properties" => %{"baz" => %{"type" => "string"}},
                "additionalProperties" => false
              }
            ]
          }
        }
      })
    end

    property "object with patternProperties" do
      check_schema(%{
        "type" => "object",
        "minProperties" => 3,
        "additionalProperties" => false,
        "patternProperties" => %{
          "^[A-Z][A-Z_]{2,}$" => %{"type" => "string", "minLength" => 1}
        }
      })
    end

    property "'not' clause filters out values" do
      check_schema(%{
        "type" => "integer",
        "minimum" => 0,
        "maximum" => 10,
        "not" => %{"enum" => [3, 9]}
      })
    end

    property "'not' clause with refs" do
      check_schema(%{
        "$defs" => %{
          "zero" => %{"const" => 0}
        },
        "type" => "number",
        "not" => %{"$ref" => "#/$defs/zero"}
      })
    end

    property "object with limited properties" do
      check_schema(%{
        "type" => "object",
        "minProperties" => 1,
        "maxProperties" => 20,
        "properties" => %{
          "name" => %{"type" => "string"},
          "address" => %{"type" => "string"},
          "birthDate" => %{"type" => "string", "format" => "date"}
        },
        "required" => ["name", "birthDate"],
        "patternProperties" => %{
          "^[A-Z][a-zA-Z]+" => %{"type" => "string", "pattern" => "^[a-zA-Z]+"}
        },
        "additionalProperties" => false
      })
    end

    property "object with dependentRequired" do
      check_schema(%{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "firstName" => %{"type" => "string"},
          "lastName" => %{"type" => "string"},
          "age" => %{"type" => "integer"},
          "birthDate" => %{"type" => "string", "format" => "date"}
        },
        "required" => ["name"],
        "dependentRequired" => %{
          "firstName" => ["lastName"],
          "lastName" => ["firstName"],
          "age" => ["birthDate"]
        }
      })
    end

    property "array with limited options and uniqueItems" do
      check_schema(%{
        "type" => "array",
        "uniqueItems" => true,
        "items" => %{"type" => "integer", "minimum" => 0, "maximum" => 2}
      })
    end

    property "array with enum options and uniqueItems" do
      check_schema(%{
        "$defs" => %{"names" => %{"enum" => ["Alice", "Bob"]}},
        "type" => "array",
        "items" => %{"$ref" => "#/$defs/names"},
        "uniqueItems" => true
      })
    end

    property "array with prefix items" do
      check_schema(%{
        "type" => "array",
        "prefixItems" => [%{"type" => "number"}],
        "items" => false
      })
    end

    property "array without prefix items" do
      check_schema(%{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{
            "name" => %{"type" => "string"},
            "admin" => %{"anyOf" => [%{"type" => "boolean"}, %{"type" => "null"}]}
          },
          "required" => ["name"],
          "additionalProperties" => false
        }
      })
    end

    property "array with uniqueItems" do
      check_schema(%{
        "type" => "array",
        "items" => %{
          "type" => "object",
          "properties" => %{"name" => %{"type" => "string"}},
          "required" => ["name"],
          "additionalProperties" => false
        },
        "uniqueItems" => true
      })
    end

    property "const generates always the same value" do
      check_schema(%{"const" => %{"hello" => ["world"]}})
    end

    property "enum generates from a set of values" do
      check_schema(%{"enum" => ["one", "two", "four"]})
    end

    property "self-referencing schema" do
      check_schema(%{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "other" => %{"$ref" => "#"}
        },
        "additionalProperties" => false
      })
    end

    property "oneOf + allOf" do
      check_schema(%{
        "$defs" => %{
          "bar" => %{"type" => "boolean"},
          "foo" => %{
            "oneOf" => [
              %{"properties" => %{"bar" => %{"$ref" => "#/$defs/bar"}}},
              %{
                "properties" => %{
                  "bar" => %{"type" => "array", "items" => %{"$ref" => "#/$defs/bar"}}
                }
              }
            ]
          }
        },
        "allOf" => [%{"$ref" => "#/$defs/foo"}],
        "properties" => %{"baz" => %{"type" => "string"}}
      })
    end

    property "oneOf schemas" do
      check_schema(%{
        "type" => "object",
        "oneOf" => [
          %{
            "properties" => %{"name" => %{"type" => "string"}},
            "additionalProperties" => false
          },
          %{
            "additionalProperties" => false,
            "properties" => %{
              "fistName" => %{"type" => "string"},
              "lastName" => %{"type" => "string"}
            }
          }
        ]
      })
    end

    property "$ref generates from the referenced subschema" do
      check_schema(%{
        "$defs" => %{
          "person" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{"type" => "string"},
              "age" => %{"type" => "integer", "minimum" => 0}
            }
          }
        },
        "type" => "array",
        "items" => %{"$ref" => "#/$defs/person"}
      })
    end

    property "enum and not with refs" do
      check_schema(%{
        "type" => "object",
        "properties" => %{
          "destination" => %{
            "enum" => ["USA", "Canada", "France"],
            "type" => "string",
            "not" => %{"$ref" => "#/properties/homeCountry"}
          },
          "homeCountry" => %{"const" => "USA"}
        }
      })
    end

    property "object with additionalProperties only" do
      check_schema(%{
        "type" => "object",
        "additionalProperties" => %{"type" => "string"},
        "maxProperties" => 3
      })
    end

    property "dependencies as anyOf dependentSchemas" do
      check_schema(%{
        "type" => "object",
        "properties" => %{"foo" => %{"type" => "string"}},
        "dependencies" => %{
          "foo" => %{"anyOf" => [%{"required" => ["bar"]}, %{"required" => ["baz"]}]}
        }
      })
    end
  end

  defp check_schema(schema) do
    root = JSV.build!(schema, resolver: [RockSolid.Resolver])

    check all generated <- RockSolid.from_schema(schema) do
      assert {:ok, _} = JSV.validate(generated, root)
    end
  end
end
