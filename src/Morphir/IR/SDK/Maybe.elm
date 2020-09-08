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


module Morphir.IR.SDK.Maybe exposing (..)

import Dict
import Morphir.IR.Documented exposing (Documented)
import Morphir.IR.Module as Module exposing (ModulePath)
import Morphir.IR.Name as Name
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.SDK.Common exposing (toFQName)
import Morphir.IR.Type as Type exposing (Specification(..), Type(..))
import Morphir.IR.Value as Value


moduleName : ModulePath
moduleName =
    Path.fromString "Maybe"


moduleSpec : Module.Specification () ()
moduleSpec =
    { types =
        Dict.fromList
            [ ( Name.fromString "Maybe"
              , CustomTypeSpecification [ Name.fromString "a" ]
                    [ Type.Constructor (Name.fromString "Just") [ ( [ "value" ], Type.Variable () (Name.fromString "a") ) ]
                    , Type.Constructor (Name.fromString "Nothing") []
                    ]
                    |> Documented "Type that represents an optional value."
              )
            ]
    , values =
        let
            -- Used temporarily as a placeholder for function values until we can generate them based on the SDK.
            dummyValueSpec : Value.Specification ()
            dummyValueSpec =
                Value.Specification [] (Type.Unit ())

            valueNames : List String
            valueNames =
                [ "andThen"
                , "map"
                , "map2"
                , "map3"
                , "map4"
                , "map5"
                , "withDefault"
                ]
        in
        valueNames
            |> List.map
                (\valueName ->
                    ( Name.fromString valueName, dummyValueSpec )
                )
            |> Dict.fromList
    }


maybeType : a -> Type a -> Type a
maybeType attributes itemType =
    Reference attributes (toFQName moduleName "Maybe") [ itemType ]
