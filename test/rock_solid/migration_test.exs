defmodule RockSolid.MigrationTest do
  use RockSolid.TestCase, async: true

  alias RockSolid.Migration
  alias RockSolid.Schemas.Vocabulary

  alias RockSolid.Resolution.Resolver.DummyResolver
  alias RockSolid.Resolvers.RemoteResolver

  describe "migrate/1" do
    test "unevaluatedProperties overrides additionalProperties if not set" do
      schema = %{
        "$id" => schema_id(),
        "type" => "object",
        "additionalProperties" => %{"type" => "string"},
        "unevaluatedProperties" => false,
        "properties" => %{
          "foo" => %{"type" => "object", "unevaluatedProperties" => false}
        }
      }

      expected = %{
        "$id" => schema["$id"],
        "additionalProperties" => %{"type" => "string"},
        "properties" => %{
          "foo" => %{
            "additionalProperties" => false,
            "type" => "object",
            "unevaluatedProperties" => false
          }
        },
        "type" => "object",
        "unevaluatedProperties" => false
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "$ref at top level inserts behaviour" do
      schema = %{
        "id" => schema_id(),
        "$schema" => Vocabulary.draft07(),
        "$ref" => "#/definitions/foo",
        "definitions" => %{
          "foo" => %{"type" => "object"}
        }
      }

      expected = %{
        "$defs" => %{"foo" => %{"type" => "object"}},
        "$id" => schema["id"],
        "$ref" => "#{schema["id"]}#/$defs/foo",
        "$schema" => Vocabulary.draft2020_12(),
        "x-rocksolid-refbehaviour" => "ignore"
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "ignores redundant ids" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{
            "id" => "#/properties/name",
            "type" => "string"
          }
        }
      }

      expected = %{
        "$id" => "root://no-uri",
        "type" => "object",
        "properties" => %{"name" => %{"type" => "string"}}
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "top level ref '#' is unmodified" do
      schema_id = schema_id()

      schema = %{
        "$id" => schema_id,
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "other" => %{"$ref" => "#{schema_id}#"}
        },
        "additionalProperties" => false
      }

      expected = put_in(schema, ["properties", "other", "x-rocksolid-refbehaviour"], "merge")
      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "unevaluatedProperties and unevaluatedItems are allowed to be false" do
      schema = %{
        "$id" => schema_id(),
        "type" => "object",
        "additionalProperties" => false,
        "unevaluatedProperties" => false,
        "properties" => %{
          "names" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "unevaluatedItems" => false
          }
        }
      }

      assert {:ok, schema} == Migration.migrate(schema, DummyResolver)
    end

    test "unevaluatedProperties and unevaluatedItems return error if not false" do
      schema = %{
        "type" => "object",
        "unevaluatedProperties" => %{"type" => "string"},
        "properties" => %{
          "names" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "unevaluatedItems" => false
          }
        }
      }

      assert {:error, "unsupported keyword 'unevaluatedProperties'" <> _} =
               Migration.migrate(schema, DummyResolver)
    end

    test "returns error for unsupported keywords" do
      schema = %{
        "$id" => "https://example.com",
        "type" => "array",
        "items" => %{"type" => "string"},
        "maxContains" => 20
      }

      assert {:error, "unsupported keyword 'maxContains' in '#'"} ==
               Migration.migrate(schema, DummyResolver)
    end

    test "replaces '$anchor' id with path in ref" do
      schema = %{
        "$id" => schema_id(),
        "$ref" => "#person",
        "$defs" => %{
          "person" => %{
            "$anchor" => "person",
            "type" => "object",
            "properties" => %{
              "pets" => %{"type" => "array", "prefixItems" => [%{"$ref" => "#pet"}]}
            }
          },
          "pet" => %{
            "$anchor" => "pet",
            "type" => "object",
            "properties" => %{"name" => %{"type" => "string"}}
          }
        }
      }

      expected = %{
        "$defs" => %{
          "person" => %{
            "$anchor" => "person",
            "properties" => %{
              "pets" => %{
                "prefixItems" => [
                  %{
                    "$ref" => "#{schema["$id"]}#/$defs/pet",
                    "x-rocksolid-refbehaviour" => "merge"
                  }
                ],
                "type" => "array"
              }
            },
            "type" => "object"
          },
          "pet" => %{
            "$anchor" => "pet",
            "properties" => %{"name" => %{"type" => "string"}},
            "type" => "object"
          }
        },
        "x-rocksolid-refbehaviour" => "merge",
        "$ref" => "#{schema["$id"]}#/$defs/person",
        "$id" => schema["$id"]
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "ignores empty $defs" do
      schema = %{"$defs" => %{}, "type" => "object", "$id" => schema_id()}

      assert {:ok, %{"type" => "object", "$id" => schema["$id"]}} ==
               Migration.migrate(schema, DummyResolver)
    end

    test "replaces 'id' with '$id' in non-properties" do
      schema = %{
        "id" => schema_id(),
        "type" => "object",
        "properties" => %{"id" => %{"type" => "string"}},
        "$defs" => %{"person" => %{"id" => "#/$defs/person", "type" => "string"}}
      }

      expected = %{
        "$id" => schema["id"],
        "type" => "object",
        "properties" => %{"id" => %{"type" => "string"}},
        "$defs" => %{"person" => %{"type" => "string"}}
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "replaces 'definitions' with '$defs'" do
      schema = %{
        "$id" => schema_id(),
        "$schema" => Vocabulary.draft04(),
        "definitions" => %{
          "person" => %{"properties" => %{"definitions" => %{"type" => "string"}}},
          "people" => %{
            "type" => "array",
            "items" => %{"$ref" => "#/definitions/person"}
          }
        }
      }

      expected = %{
        "$id" => schema["$id"],
        "$schema" => Vocabulary.draft2020_12(),
        "$defs" => %{
          "person" => %{"properties" => %{"definitions" => %{"type" => "string"}}},
          "people" => %{
            "type" => "array",
            "items" => %{
              "$ref" => "#{schema["$id"]}#/$defs/person",
              "x-rocksolid-refbehaviour" => "ignore"
            }
          }
        }
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "replaces boolean exclusiveMinimum and exclusiveMaximum" do
      schema = %{
        "type" => "obect",
        "$id" => schema_id(),
        "properties" => %{
          "age" => %{
            "minimum" => 0,
            "exclusiveMinimum" => true,
            "maximum" => 130,
            "exclusiveMaximum" => true
          }
        }
      }

      expected = %{
        "$id" => schema["$id"],
        "type" => "obect",
        "properties" => %{"age" => %{"exclusiveMinimum" => 0, "exclusiveMaximum" => 130}}
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "converts dependencies to dependentRequired and dependentSchemas" do
      schema = %{
        "$id" => schema_id(),
        "type" => "object",
        "dependencies" => %{
          "name" => ["firstName", "lastName"],
          "pet" => ["animal"],
          "age" => %{"properties" => %{"birthDate" => %{"type" => "string"}}},
          "address" => %{"properties" => %{"country" => %{"enum" => ["USA"]}}}
        },
        "properties" => %{"countryObject" => %{"$ref" => "#/dependencies/address"}}
      }

      expected = %{
        "$id" => schema["$id"],
        "type" => "object",
        "dependentRequired" => %{"name" => ["firstName", "lastName"], "pet" => ["animal"]},
        "dependentSchemas" => %{
          "age" => %{"properties" => %{"birthDate" => %{"type" => "string"}}, "type" => "object"},
          "address" => %{"properties" => %{"country" => %{"enum" => ["USA"]}}, "type" => "object"}
        },
        "properties" => %{
          "countryObject" => %{
            "x-rocksolid-refbehaviour" => "merge",
            "$ref" => "#{schema["$id"]}#/dependentSchemas/address"
          }
        }
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "replaces empty dicts by true except for properties and patternProperties" do
      schema = %{
        "$id" => schema_id(),
        "type" => "object",
        "definitions" => %{
          "testObject" => %{
            "type" => "object",
            "properties" => %{},
            "patternProperties" => %{},
            "additionalProperties" => %{}
          }
        }
      }

      expected = %{
        "$id" => schema["$id"],
        "type" => "object",
        "$defs" => %{
          "testObject" => %{
            "type" => "object",
            "properties" => %{},
            "patternProperties" => %{},
            "additionalProperties" => true
          }
        }
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "items as array with additionalItems are converted to prefixItems" do
      schema = %{
        "$id" => schema_id(),
        "definitions" => %{
          "person" => %{
            "properties" => %{
              "names" => %{
                "items" => [%{"type" => "string"}, %{"type" => "string"}],
                "additionalItems" => %{"type" => "number"}
              }
            }
          },
          "firstName" => %{"$ref" => "#/definitions/person/properties/names/items/0"},
          "age" => %{"$ref" => "#/definitions/person/properties/names/additionalItems"}
        }
      }

      expected = %{
        "$id" => schema["$id"],
        "$defs" => %{
          "person" => %{
            "properties" => %{
              "names" => %{
                "prefixItems" => [%{"type" => "string"}, %{"type" => "string"}],
                "items" => %{"type" => "number"}
              }
            }
          },
          "firstName" => %{
            "$ref" => "#{schema["$id"]}#/$defs/person/properties/names/prefixItems/0",
            "x-rocksolid-refbehaviour" => "merge"
          },
          "age" => %{
            "$ref" => "#{schema["$id"]}#/$defs/person/properties/names/items",
            "x-rocksolid-refbehaviour" => "merge"
          }
        }
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "does not modify example '$ref'" do
      schema = %{
        "id" => schema_id(),
        "definitions" => %{"foo" => %{"type" => "string"}},
        "properties" => %{
          "bar" => %{"const" => %{"$ref" => "#/definitions/foo"}},
          "baz" => %{"enum" => [%{"$ref" => "#/definitions/foo"}]},
          "qux" => %{"$ref" => "#/definitions/foo"}
        },
        "examples" => [
          %{"$ref" => "#/definitions/foo"}
        ]
      }

      expected = %{
        "$defs" => %{"foo" => %{"type" => "string"}},
        "$id" => schema["id"],
        "examples" => [%{"$ref" => "#/definitions/foo"}],
        "properties" => %{
          "bar" => %{"const" => %{"$ref" => "#/definitions/foo"}},
          "baz" => %{"enum" => [%{"$ref" => "#/definitions/foo"}]},
          "qux" => %{
            "$ref" => "#{schema["id"]}#/$defs/foo",
            "x-rocksolid-refbehaviour" => "merge"
          }
        }
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "does not modify examples or defaults" do
      schema = %{
        "id" => schema_id(),
        "properties" => %{
          "foo" => %{"enum" => [%{"id" => "bar"}]},
          "examples" => %{
            "const" => %{"id" => "foo"},
            "examples" => [%{"id" => "foo"}],
            "default" => %{"id" => "foo"}
          }
        }
      }

      expected = %{"$id" => schema["id"], "properties" => schema["properties"]}
      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end
  end

  describe "migration with refs" do
    test "anchor is expanded considering the scope" do
      remote_id = schema_id()

      schema = %{
        "$id" => schema_id(),
        "$defs" => %{
          "person" => %{"$anchor" => "person", "type" => "object"}
        },
        "type" => "object",
        "properties" => %{
          "people" => %{"type" => "array", "items" => %{"$ref" => "#person"}},
          "morePeople" => %{"$ref" => "#{remote_id}#person"}
        }
      }

      remote = %{"$defs" => %{"person" => %{"type" => "object", "$anchor" => "person"}}}
      Req.Test.expect(RockSolid.Client, &Req.Test.json(&1, remote))

      expected = %{
        "$id" => schema["$id"],
        "$defs" => %{
          "person" => %{"$anchor" => "person", "type" => "object"}
        },
        "type" => "object",
        "properties" => %{
          "people" => %{
            "type" => "array",
            "items" => %{
              "$ref" => "#{schema["$id"]}#/$defs/person",
              "x-rocksolid-refbehaviour" => "merge"
            }
          },
          "morePeople" => %{
            "$ref" => "#{remote_id}#/$defs/person",
            "x-rocksolid-refbehaviour" => "merge"
          }
        }
      }

      assert {:ok, expected} == Migration.migrate(schema, {RemoteResolver, []})
    end

    test "'$ref' as dependencies is treated as literal" do
      schema = %{
        "properties" => %{"$ref" => %{"type" => "string"}},
        "dependencies" => %{"$ref" => %{"required" => []}}
      }

      {:ok, value} = Migration.migrate(schema, {DummyResolver, []})

      assert value["dependentSchemas"]["$ref"] == %{"required" => [], "type" => "object"}
    end

    test "empty enum map is kept as is" do
      schema = %{"enum" => [%{}, [], true, false]}
      {:ok, value} = Migration.migrate(schema, {DummyResolver, []})

      assert value["enum"] == [%{}, [], true, false]
    end

    test "ref points to property named 'definitions" do
      schema = %{
        "$id" => schema_id(),
        "$schema" => Vocabulary.draft07(),
        "definitions" => %{"foo" => %{"type" => "string"}},
        "properties" => %{
          "definitions" => %{"$ref" => "#/definitions/foo"}
        }
      }

      expected = %{
        "$id" => schema["$id"],
        "$schema" => Vocabulary.draft2020_12(),
        "$defs" => %{"foo" => %{"type" => "string"}},
        "properties" => %{
          "definitions" => %{
            "$ref" => "#{schema["$id"]}#/$defs/foo",
            "x-rocksolid-refbehaviour" => "ignore"
          }
        }
      }

      assert {:ok, expected} == Migration.migrate(schema, {DummyResolver, []})
    end

    test "ref points to property named 'default'" do
      schema = %{
        "$id" => schema_id(),
        "$schema" => Vocabulary.draft07(),
        "properties" => %{"default" => %{"$ref" => "#/definitions/default"}},
        "definitions" => %{"default" => %{"type" => "string"}}
      }

      expected = %{
        "$defs" => %{"default" => %{"type" => "string"}},
        "$id" => schema["$id"],
        "$schema" => Vocabulary.draft2020_12(),
        "properties" => %{
          "default" => %{
            "$ref" => "#{schema["$id"]}#/$defs/default",
            "x-rocksolid-refbehaviour" => "ignore"
          }
        }
      }

      assert {:ok, expected} == Migration.migrate(schema, {DummyResolver, []})
    end

    test "ref points to relative remote schema" do
      schema = %{
        "$id" => "https://example.com/schema.json",
        "definitions" => %{
          "bar" => %{"$ref" => "remote.json#/definitions/foo"}
        },
        "properties" => %{
          "baz" => %{"$ref" => "#/definitions/bar"}
        }
      }

      remote = %{
        "$id" => "https://example.com/remote.json",
        "definitions" => %{
          "foo" => %{"type" => "number"}
        }
      }

      Req.Test.expect(RockSolid.Client, fn conn ->
        assert conn.host == "example.com"
        assert conn.request_path == "/remote.json"
        Req.Test.json(conn, remote)
      end)

      expected = %{
        "$defs" => %{
          "bar" => %{
            "$ref" => "https://example.com/remote.json#/$defs/foo",
            "x-rocksolid-refbehaviour" => "merge"
          }
        },
        "properties" => %{
          "baz" => %{
            "$ref" => "https://example.com/schema.json#/$defs/bar",
            "x-rocksolid-refbehaviour" => "merge"
          }
        },
        "$id" => "https://example.com/schema.json"
      }

      assert {:ok, expected} == Migration.migrate(schema, {RemoteResolver, []})
    end

    test "ref points to entire schema" do
      remote_uri = schema_id()
      schema = %{"$ref" => "#{remote_uri}#", "$id" => schema_id()}
      remote = %{"type" => "number", "$id" => remote_uri}

      expected_schema = %{
        "$ref" => "#{remote_uri}#",
        "$id" => schema["$id"],
        "x-rocksolid-refbehaviour" => "merge"
      }

      Req.Test.expect(RockSolid.Client, &Req.Test.json(&1, remote))

      assert {:ok, expected_schema} == Migration.migrate(schema, {RemoteResolver, []})
      assert remote == RockSolid.Context.fetch_schema!(remote_uri)
    end

    test "nested ref expands to absolute value" do
      remote_uri = schema_id()
      schema = %{"$ref" => "#{remote_uri}#/$defs/person", "$id" => schema_id()}

      remote = %{
        "$id" => remote_uri,
        "$defs" => %{
          "person" => %{
            "type" => "object",
            "properties" => %{"name" => %{"$ref" => "#/$defs/name"}}
          },
          "name" => %{"type" => "string"}
        }
      }

      expected_schema = %{
        "$ref" => "#{remote_uri}#/$defs/person",
        "$id" => schema["$id"],
        "x-rocksolid-refbehaviour" => "merge"
      }

      Req.Test.expect(RockSolid.Client, &Req.Test.json(&1, remote))
      assert {:ok, expected_schema} == Migration.migrate(schema, {RemoteResolver, []})

      expected_remote = %{
        "$id" => remote_uri,
        "$defs" => %{
          "person" => %{
            "type" => "object",
            "properties" => %{
              "name" => %{
                "x-rocksolid-refbehaviour" => "merge",
                "$ref" => "#{remote_uri}#/$defs/name"
              }
            }
          },
          "name" => %{"type" => "string"}
        }
      }

      assert expected_remote == RockSolid.Context.fetch_schema!(remote["$id"])
    end

    test "$schema as property is ignored for ref behaviour" do
      schema = %{
        "$id" => schema_id(),
        "$defs" => %{
          "foo" => %{"type" => "string"},
          "bar" => %{
            "type" => "object",
            "properties" => %{
              "$schema" => %{"type" => "string"},
              "baz" => %{"$ref" => "#/$defs/foo"}
            }
          }
        }
      }

      expected = %{
        "$defs" => %{
          "bar" => %{
            "properties" => %{
              "$schema" => %{"type" => "string"},
              "baz" => %{
                "$ref" => "#{schema["$id"]}#/$defs/foo",
                "x-rocksolid-refbehaviour" => "merge"
              }
            },
            "type" => "object"
          },
          "foo" => %{"type" => "string"}
        },
        "$id" => schema["$id"]
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end

    test "ref behaviour is adapted to the most immediate top $schema" do
      schema = %{
        "$id" => schema_id(),
        "$schema" => Vocabulary.draft2020_12(),
        "$ref" => "#/$defs/foo",
        "$defs" => %{
          "foo" => %{
            "$schema" => Vocabulary.draft07(),
            "type" => "array",
            "items" => %{"$ref" => "#/$defs/bar"}
          },
          "bar" => %{"type" => "string"}
        }
      }

      expected = %{
        "$id" => schema["$id"],
        "$schema" => Vocabulary.draft2020_12(),
        "x-rocksolid-refbehaviour" => "merge",
        "$ref" => "#{schema["$id"]}#/$defs/foo",
        "$defs" => %{
          "foo" => %{
            "$schema" => Vocabulary.draft2020_12(),
            "type" => "array",
            "items" => %{
              "$ref" => "#{schema["$id"]}#/$defs/bar",
              "x-rocksolid-refbehaviour" => "ignore"
            }
          },
          "bar" => %{"type" => "string"}
        }
      }

      assert {:ok, expected} == Migration.migrate(schema, DummyResolver)
    end
  end
end
