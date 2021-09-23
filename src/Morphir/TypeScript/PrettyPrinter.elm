module Morphir.TypeScript.PrettyPrinter exposing
    ( Options, mapCompilationUnit, mapTypeDef, mapTypeExp
    , mapObjectExp
    )

{-| This module contains a pretty-printer that takes a TypeScript AST as an input and returns a formatted text
representation.

@docs Options, mapCompilationUnit, mapTypeDef, mapTypeExp

-}

import Morphir.File.SourceCode exposing (Doc, concat, empty, indentLines, newLine)
import Morphir.TypeScript.AST exposing (CompilationUnit, ObjectExp, TypeDef(..), TypeExp(..))


{-| Formatting options.
-}
type alias Options =
    { indentDepth : Int
    }


{-| -}
mapCompilationUnit : Options -> CompilationUnit -> Doc
mapCompilationUnit opt cu =
    concat
        [ "// Generated by morphir-elm"
        , newLine
        , cu.typeDefs
            |> List.map (mapTypeDef opt)
            |> String.join (newLine ++ newLine)
        , newLine
        ]


{-| Map a type definition to text.
-}
mapGenericVariables : List String -> String
mapGenericVariables variables =
    case List.length variables of
        0 ->
            ""

        _ ->
            concat
                [ "<"
                , String.join ", " variables
                , ">"
                ]


mapTypeDef : Options -> TypeDef -> Doc
mapTypeDef opt typeDef =
    case typeDef of
        TypeAlias name variables typeExp ->
            concat
                [ "type "
                , name
                , mapGenericVariables variables
                , " = "
                , mapTypeExp opt typeExp
                ]

        Interface name variables fields ->
            concat
                [ "interface "
                , name
                , mapGenericVariables variables
                , mapObjectExp opt fields
                ]


{-| Map an object expression or interface definiton to text
-}
mapObjectExp : Options -> ObjectExp -> Doc
mapObjectExp opt objectExp =
    let
        mapField : ( String, TypeExp ) -> Doc
        mapField ( fieldName, fieldType ) =
            concat [ fieldName, ": ", mapTypeExp opt fieldType, ";" ]
    in
    concat
        [ "{"
        , newLine
        , objectExp
            |> List.map mapField
            |> indentLines opt.indentDepth
        , newLine
        , "}"
        ]


{-| Map a type expression to text.
-}
mapTypeExp : Options -> TypeExp -> Doc
mapTypeExp opt typeExp =
    case typeExp of
        Any ->
            "any"

        Boolean ->
            "boolean"

        List listType ->
            "Array<" ++ mapTypeExp opt listType ++ ">"

        LiteralString stringval ->
            "\"" ++ stringval ++ "\""

        Number ->
            "number"

        Object fieldList ->
            mapObjectExp opt fieldList

        String ->
            "string"

        Tuple tupleTypesList ->
            concat
                [ "["
                , tupleTypesList
                    |> List.map (mapTypeExp opt)
                    |> String.join ", "
                , "]"
                ]

        TypeRef name variables ->
            name ++ mapGenericVariables variables

        Union types ->
            types |> List.map (mapTypeExp opt) |> String.join " | "

        Variable name ->
            name

        UnhandledType tpe ->
            concat
                [ "any"
                , " /* Unhandled type: "
                , tpe
                , " */"
                ]
