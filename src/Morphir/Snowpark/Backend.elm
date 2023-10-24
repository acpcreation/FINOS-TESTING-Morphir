module Morphir.Snowpark.Backend exposing (..)

import Dict
import List
import Morphir.File.FileMap exposing (FileMap)
import Morphir.IR.AccessControlled exposing (Access(..), AccessControlled)
import Morphir.IR.Distribution as Distribution exposing (..)
import Morphir.IR.Name as Name
import Morphir.IR.Package as Package
import Morphir.IR.Module as Module 
import Morphir.IR.Path as Path exposing (Path)
import Morphir.IR.Type exposing (Type)
import Morphir.Scala.AST as Scala
import Morphir.Scala.PrettyPrinter as PrettyPrinter
import Morphir.TypeSpec.Backend exposing (mapModuleDefinition)
import Morphir.Scala.Common exposing (mapValueName)
import Morphir.IR.Value as Value exposing (Pattern(..), Value(..))
import Morphir.Snowpark.MappingContext as MappingContext exposing (emptyValueMappingContext)
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.Snowpark.Constants as Constants
import Morphir.Snowpark.RecordWrapperGenerator as RecordWrapperGenerator
import Morphir.Snowpark.MappingContext exposing (MappingContextInfo)
import Morphir.Snowpark.AccessElementMapping exposing (
    mapFieldAccess
    , mapReferenceAccess
    , mapVariableAccess
    , mapConstructorAccess)
import Morphir.IR.Documented exposing (Documented)
import Morphir.Visual.BoolOperatorTree exposing (functionName)
import Morphir.IR.Type as Type
import Morphir.Snowpark.MappingContext exposing (isRecordWithSimpleTypes)
import Morphir.Snowpark.ReferenceUtils exposing (isTypeReferenceToSimpleTypesRecord, mapLiteral)
import Morphir.Snowpark.TypeRefMapping exposing (mapTypeReference)
import Morphir.Snowpark.MappingContext exposing (ValueMappingContext)
import Morphir.Snowpark.MapFunctionsMapping as MapFunctionsMapping
import Morphir.Snowpark.PatternMatchMapping exposing (mapPatternMatch)

type alias Options =
    {}

mapDistribution : Options -> Distribution -> FileMap
mapDistribution _ distro =
    case distro of
        Distribution.Library packageName _ packageDef ->
            mapPackageDefinition distro packageName packageDef


mapPackageDefinition : Distribution -> Package.PackageName -> Package.Definition () (Type ()) -> FileMap
mapPackageDefinition _ packagePath packageDef =
    let
        contextInfo = MappingContext.processDistributionModules packagePath packageDef
        generatedScala =
            packageDef.modules
                |> Dict.toList
                |> List.concatMap
                    (\( modulePath, moduleImpl ) ->
                        mapModuleDefinition packagePath modulePath moduleImpl contextInfo
                    )
    in
    generatedScala
        |> List.map
            (\compilationUnit ->
                let
                    fileContent =
                        compilationUnit
                            |> PrettyPrinter.mapCompilationUnit (PrettyPrinter.Options 2 80)
                in
                ( ( compilationUnit.dirPath, compilationUnit.fileName ), fileContent )
            )
        |> Dict.fromList


mapModuleDefinition : Package.PackageName -> Path -> AccessControlled (Module.Definition () (Type ())) -> MappingContextInfo () -> List Scala.CompilationUnit
mapModuleDefinition currentPackagePath currentModulePath accessControlledModuleDef mappingCtx =
    let
        ( scalaPackagePath, moduleName ) =
            case currentModulePath |> List.reverse of
                [] ->
                    ( [], [] )

                lastName :: reverseModulePath ->
                    let
                        parts =
                            List.append currentPackagePath (List.reverse reverseModulePath)
                    in
                    ( parts |> (List.map Name.toCamelCase), lastName )

        moduleTypeDefinitions : List (Scala.Annotated Scala.MemberDecl)
        moduleTypeDefinitions = 
            accessControlledModuleDef.value.types
                |> RecordWrapperGenerator.generateRecordWrappers currentPackagePath currentModulePath mappingCtx
                |> List.map (\doc -> { annotations = doc.value.annotations, value = Scala.MemberTypeDecl (doc.value.value) } )

        functionMembers : List (Scala.Annotated Scala.MemberDecl)
        functionMembers =
            accessControlledModuleDef.value.values
                |> Dict.toList
                |> List.concatMap
                    (\( valueName, accessControlledValueDef ) ->
                        [ mapFunctionDefinition valueName accessControlledValueDef currentPackagePath mappingCtx
                        ]
                    )
                |> List.map Scala.withoutAnnotation
        moduleUnit : Scala.CompilationUnit
        moduleUnit =
            { dirPath = scalaPackagePath
            , fileName = (moduleName |> Name.toTitleCase) ++ ".scala"
            , packageDecl = scalaPackagePath
            , imports = []
            , typeDecls = [( Scala.Documented (Just (String.join "" [ "Generated based on ", currentModulePath |> Path.toString Name.toTitleCase "." ]))
                    (Scala.Annotated []
                        (Scala.Object
                            { modifiers =
                                case accessControlledModuleDef.access of
                                    Public ->
                                        []

                                    Private ->
                                        []
                            , name =
                                moduleName |> Name.toTitleCase
                            , members = 
                                (moduleTypeDefinitions ++ functionMembers)
                            , extends =
                                []
                            , body = Nothing
                            }
                        )
                    )
                )]
            }
    in
    [ moduleUnit ]


mapFunctionDefinition : Name.Name -> AccessControlled (Documented (Value.Definition () (Type ()))) ->  Path ->  MappingContextInfo () -> Scala.MemberDecl
mapFunctionDefinition functionName body currentPackagePath mappingCtx =
    let
       (parameters, localVariables) = processParameters body.value.value.inputTypes mappingCtx
       parameterNames = body.value.value.inputTypes |> List.map (\(name, _, _) -> name)
       valueMappingContext = { emptyValueMappingContext | typesContextInfo = mappingCtx, parameters = parameterNames, packagePath = currentPackagePath} 
       bodyCandidate = mapFunctionBody body.value.value valueMappingContext 
       
       resultingBody = case (localVariables, bodyCandidate) of
                            ([], _) -> bodyCandidate
                            (declarations, Just bodyToUse) -> Just (Scala.Block declarations bodyToUse)
                            (_, _) -> Nothing
       
       returnTypeToGenerate = mapTypeReference body.value.value.outputType mappingCtx
    in
    Scala.FunctionDecl
            { modifiers = []
            , name = mapValueName functionName
            , typeArgs = []                                
            , args = parameters
            , returnType = 
                Just returnTypeToGenerate
            , body =
                resultingBody
            }

generateLocalVariableForRowRecord : MappingContextInfo () -> ( Name.Name, Type (), Type a ) -> Scala.MemberDecl
generateLocalVariableForRowRecord ctx (name, _, tpe) =
   let
      nameInfo =  isTypeReferenceToSimpleTypesRecord tpe ctx
      typeNameInfo = Maybe.map 
                           (\(typePath, simpleTypeName) -> Just (Scala.TypeRef typePath (simpleTypeName |> Name.toTitleCase) ))
                           nameInfo
      objectReference = Maybe.map 
                           (\(typePath, simpleTypeName) -> Scala.Ref typePath (simpleTypeName |> Name.toTitleCase))
                           nameInfo
   in
   Scala.ValueDecl {
    modifiers = []
    , pattern = (Scala.NamedMatch (name |> Name.toCamelCase))
    , valueType = Maybe.withDefault Nothing typeNameInfo
    , value = Maybe.withDefault Scala.Unit objectReference
    }
    
generateArgumentDeclarationForFunction : MappingContextInfo () -> ( Name.Name, Type (), Type () ) -> List Scala.ArgDecl
generateArgumentDeclarationForFunction ctx (name, _, tpe) =
    [Scala.ArgDecl [] (mapTypeReference tpe ctx) (name |> Name.toCamelCase) Nothing]

processParameters : List ( Name.Name, Type (), Type () ) -> MappingContextInfo () -> (List (List Scala.ArgDecl), List (Scala.MemberDecl) )
processParameters inputTypes ctx =
    let
        recWithSimpleTypesPred : ( Name.Name, Type (), Type a ) -> Bool
        recWithSimpleTypesPred tpe = 
            case tpe of
                (_, _, Type.Reference _ fqName []) -> not(isRecordWithSimpleTypes fqName ctx)
                _ -> True
        (typesToProcess, typesWithRecords) = inputTypes |> List.partition recWithSimpleTypesPred
    in
    (typesToProcess |> List.map (generateArgumentDeclarationForFunction ctx),
     typesWithRecords |> List.map (generateLocalVariableForRowRecord ctx))


mapFunctionBody : Value.Definition ta (Type ()) -> ValueMappingContext -> Maybe Scala.Value
mapFunctionBody value ctx =
           Maybe.Just (mapValue value.body ctx)

mapValue : Value ta (Type ()) -> ValueMappingContext -> Scala.Value
mapValue value ctx =
    case value of
        Literal tpe literal ->
            mapLiteral tpe literal
        Field tpe val name ->
            mapFieldAccess tpe val name ctx
        Variable tpe name ->
            mapVariableAccess tpe name ctx
        Constructor tpe name ->
            mapConstructorAccess tpe name ctx
        List _ values ->
            Scala.Apply 
                (Scala.Variable "Seq")
                (values |> List.map (\v -> Scala.ArgValue Nothing (mapValue v ctx)))
        Reference tpe name ->
            mapReferenceAccess tpe name
        Apply _ _ _ ->
            MapFunctionsMapping.mapFunctionsMapping value mapValue ctx
        PatternMatch tpe expr cases ->
            mapPatternMatch (tpe, expr, cases) mapValue ctx
        IfThenElse _ condition thenExpr elseExpr ->
            mapIfThenElse condition thenExpr elseExpr ctx
        _ ->
            Scala.Literal (Scala.StringLit ("Unsupported element"))


mapIfThenElse : Value ta (Type ()) -> Value ta (Type ()) -> Value ta (Type ()) -> ValueMappingContext -> Scala.Value
mapIfThenElse condition thenExpr elseExpr ctx =
   let
       whenCall = 
            Constants.applySnowparkFunc "when" [ mapValue condition ctx,  mapValue thenExpr ctx ]
   in
   Scala.Apply (Scala.Select whenCall "otherwise") [Scala.ArgValue Nothing (mapValue elseExpr ctx)]
