module Morphir.JsonSchema.Backend exposing (..)

{-| This module encapsulates the JSON Schema backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated. The consumer is responsible for getting the input IR and saving the output
to the file-system.
-}

{-
   Copyright 2020 Morgan Stanley

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}

import Dict exposing (Dict)
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (AccessControlled, withPublicAccess)
import Morphir.IR.Distribution as Distribution exposing (Distribution)
import Morphir.IR.FQName as FQName
import Morphir.IR.Module as Module exposing (ModuleName)
import Morphir.IR.Name as Name exposing (Name)
import Morphir.IR.Package as Package exposing (PackageName)
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type as Type exposing (Type(..))
import Morphir.JsonSchema.AST as Type exposing (Schema, SchemaType(..), TypeName)
import Morphir.JsonSchema.PrettyPrinter exposing (encodeSchema)


type alias Options =
    {}


type alias QualifiedName =
    ( Path, Name )


type Error
    = Error


{-| Entry point for the JSON Schema backend. It takes the Morphir IR as the input and returns an in-memory
representation of files generated.
-}
mapDistribution : Options -> Distribution -> FileMap
mapDistribution opt distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition packageName packageDef


mapPackageDefinition : PackageName -> Package.Definition ta (Type ()) -> FileMap
mapPackageDefinition packageName packageDefinition =
    packageDefinition
        |> generateSchema packageName
        |> encodeSchema
        |> Dict.singleton ( [], Path.toString Name.toTitleCase "." packageName ++ ".json" )


mapQualifiedName : ( Path, Name ) -> String
mapQualifiedName ( path, name ) =
    String.join "." [ Path.toString Name.toTitleCase "." path, Name.toTitleCase name ]


generateSchema : PackageName -> Package.Definition ta (Type ()) -> Schema
generateSchema packageName packageDefinition =
    let
        schemaTypeDefinitions =
            packageDefinition.modules
                |> Dict.foldl
                    (\modName modDef listSoFar ->
                        extractTypes modName modDef.value
                            |> List.concatMap
                                (\( qualifiedName, typeDef ) ->
                                    mapTypeDefinition qualifiedName typeDef
                                )
                            |> (\lst -> listSoFar ++ lst)
                    )
                    []
                |> Dict.fromList
    in
    { dirPath = []
    , fileName = ""
    , id = "https://morphir.finos.org/" ++ Path.toString Name.toSnakeCase "-" packageName ++ ".schema.json"
    , schemaVersion = "https://json-schema.org/draft/2020-12/schema"
    , definitions = schemaTypeDefinitions
    }


extractTypes : ModuleName -> Module.Definition ta (Type ()) -> List ( QualifiedName, Type.Definition ta )
extractTypes modName definition =
    definition.types
        |> Dict.toList
        |> List.map
            (\( name, accessControlled ) ->
                ( ( modName, name ), accessControlled.value.value )
            )


mapTypeDefinition : ( Path, Name ) -> Type.Definition ta -> List ( TypeName, SchemaType )
mapTypeDefinition qualifiedName definition =
    case definition of
        Type.TypeAliasDefinition typeArgs typ ->
            [ ( mapQualifiedName qualifiedName, mapType typ ) ]

        Type.CustomTypeDefinition typeArgs accessControlledCtors ->
            case accessControlledCtors.value |> Dict.toList of
                -- Just one Constructor
                [ ( ctorName, ctorArgs ) ] ->
                    -- Constructor name is same as type name
                    if ctorName == Tuple.second qualifiedName then
                        -- Just one argument
                        if List.length ctorArgs == 1 then
                            let
                                schemaType =
                                    case ctorArgs |> List.head of
                                        Just item ->
                                            mapType (Tuple.second item)

                                        Nothing ->
                                            Null
                            in
                            [ ( Tuple.second qualifiedName |> Name.toTitleCase, schemaType ) ]

                        else
                            []

                    else
                        []

                _ ->
                    []


mapType : Type ta -> SchemaType
mapType typ =
    case typ of
        Type.Reference a fQName types ->
            case FQName.toString fQName of
                "Morphir.SDK:Basics:int" ->
                    Integer

                "Morphir.SDK:String:string" ->
                    String

                "Morphir.SDK:Basics:float" ->
                    Number

                "Morphir.SDK:Basics:bool" ->
                    Boolean

                "Morphir.SDK:List:list" ->
                    case List.head types of
                        Just tpe ->
                            mapType tpe

                        Nothing ->
                            Null

                _ ->
                    Null

        Type.Record a fields ->
            fields
                |> List.foldl
                    (\field ->
                        \dictSofar ->
                            Dict.insert (Name.toTitleCase field.name) (mapType field.tpe) dictSofar
                    )
                    Dict.empty
                |> Object

        _ ->
            Null
