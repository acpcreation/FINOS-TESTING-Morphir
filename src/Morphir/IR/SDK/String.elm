module Morphir.IR.SDK.String exposing (..)

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
    [ [ "string" ] ]


moduleDeclaration : Module.Declaration ()
moduleDeclaration =
    { types =
        Dict.fromList
            [ ( [ "string" ], OpaqueTypeDeclaration [] )
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


stringType : extra -> Type extra
stringType extra =
    Reference (fromLocalName "string") [] extra
