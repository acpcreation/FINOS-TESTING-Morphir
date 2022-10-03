module Morphir.JsonSchema.PrettyPrinter exposing (..)

import Dict exposing (Dict)
import Json.Encode as Encode
import Morphir.JsonSchema.AST exposing (Schema, SchemaType(..), TypeName)


encodeSchema : Schema -> String
encodeSchema schema =
    Encode.object
        [ ( "$id", Encode.string (schema.id ++ ".schema.json") )
        , ( "$schema", Encode.string schema.schemaVersion )
        , ( "$defs", encodeDefinitions schema.definitions )
        ]
        |> Encode.encode 4


encodeDefinitions : Dict TypeName SchemaType -> Encode.Value
encodeDefinitions schemaTypeByTypeName =
    Encode.dict identity encodeSchemaType schemaTypeByTypeName


encodeSchemaType : SchemaType -> Encode.Value
encodeSchemaType schemaType =
    case schemaType of
        Integer ->
            Encode.object
                [ ( "type", Encode.string "integer" ) ]

        Array st ->
            Encode.object
                [ ( "type", Encode.string "array" )
                , ( "items", encodeSchemaType st )
                ]

        String ->
            Encode.object
                [ ( "type", Encode.string "string" ) ]

        Number ->
            Encode.object
                [ ( "type", Encode.string "number" ) ]

        Boolean ->
            Encode.object
                [ ( "type", Encode.string "boolean" ) ]

        Object st ->
            Encode.object
                [ ( "type", Encode.string "object" )
                , ( "properties", Encode.dict identity encodeSchemaType st )
                ]

        Null ->
            Encode.null
