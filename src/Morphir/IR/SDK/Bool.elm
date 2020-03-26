module Morphir.IR.SDK.Bool exposing (..)

import Dict
import Morphir.IR.Advanced.Module as Module
import Morphir.IR.Advanced.Type exposing (Declaration(..), Type(..))
import Morphir.IR.FQName as FQName exposing (FQName)
import Morphir.IR.Name as Name
import Morphir.IR.Path exposing (Path)
import Morphir.IR.QName as QName
import Morphir.IR.SDK.Common exposing (packageName)


moduleName : Path
moduleName =
    [ [ "bool" ] ]


moduleDeclaration : Module.Declaration ()
moduleDeclaration =
    { types =
        Dict.fromList
            [ ( [ "bool" ], OpaqueTypeDeclaration [] )
            ]
    , values =
        Dict.empty
    }


fromLocalName : String -> FQName
fromLocalName name =
    name
        |> Name.fromString
        |> QName.fromName moduleName
        |> FQName.fromQName packageName


boolType : extra -> Type extra
boolType extra =
    Reference (fromLocalName "bool") [] extra
