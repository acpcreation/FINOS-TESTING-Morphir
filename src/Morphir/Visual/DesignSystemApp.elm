module Morphir.Visual.DesignSystemApp exposing (..)

import Array exposing (Array)
import Browser
import Dict
import Element exposing (Color, Element, column, el, height, htmlAttribute, layout, none, padding, paddingEach, px, rgb, row, spacing, text, width)
import Element.Background as Background
import Element.Border as Border
import Element.Events as Events
import Element.Font as Font
import Element.Input as Input
import FontAwesome.Styles as Icon
import Html exposing (Html)
import Html.Attributes
import Morphir.IR.Literal exposing (Literal(..))
import Morphir.IR.Name as Name
import Morphir.IR.SDK.LocalDate as LocalDate
import Morphir.IR.Value as Value exposing (Value)
import Morphir.SDK.Decimal as Decimal
import Morphir.Visual.Components.DrillDownPanel as DrillDownPanel
import Morphir.Visual.Components.Picklist as Picklist
import Morphir.Visual.Components.TabsComponent as TabsComponent
import Morphir.Visual.Theme as Theme exposing (Colors, Theme)
import Morphir.Visual.ViewDifference exposing (viewValueDifference)


main : Program () Model Msg
main =
    Browser.sandbox
        { init = init
        , view = view
        , update = update
        }


type alias Model =
    Components


type alias Components =
    { theme : Theme
    , highlightingColor : Bool
    , activeTab : Int
    , drillDownIsOpen : Bool
    , picklist : Picklist.State Int
    }


type Msg
    = DoNothing
    | IncreaseFontSize
    | DecreaseFontSize
    | HighlightColor (Colors -> Colors)
    | SwitchTab Int
    | OpenDrillDown
    | CloseDrillDown
    | PicklistChanged (Picklist.State Int)


init : Model
init =
    let
        theme =
            Theme.fromConfig Nothing

        adjustedTheme =
            { theme
                | fontSize = 12
            }

        components : Components
        components =
            { theme = adjustedTheme
            , highlightingColor = False
            , activeTab = 0
            , drillDownIsOpen = False
            , picklist = Picklist.init Nothing
            }
    in
    components


update : Msg -> Model -> Model
update msg model =
    case msg of
        DoNothing ->
            model

        PicklistChanged newState ->
            { model
                | picklist = newState
            }

        SwitchTab newActiveTab ->
            { model
                | activeTab = newActiveTab
            }

        OpenDrillDown ->
            { model
                | drillDownIsOpen = True
            }

        CloseDrillDown ->
            { model
                | drillDownIsOpen = False
            }

        HighlightColor updateColors ->
            let
                theme =
                    model.theme

                defaultTheme =
                    Theme.fromConfig Nothing
            in
            if model.highlightingColor then
                { model
                    | theme =
                        { theme
                            | colors = defaultTheme.colors
                        }
                    , highlightingColor = False
                }

            else
                { model
                    | theme =
                        { theme
                            | colors = updateColors theme.colors
                        }
                    , highlightingColor = True
                }

        IncreaseFontSize ->
            let
                theme =
                    model.theme
            in
            { model
                | theme =
                    { theme
                        | fontSize = theme.fontSize + 4
                    }
            }

        DecreaseFontSize ->
            let
                theme =
                    model.theme
            in
            { model
                | theme =
                    { theme
                        | fontSize = theme.fontSize - 4
                    }
            }


view : Model -> Html Msg
view model =
    Html.div []
        [ Icon.css
        , layout [ Font.size 12 ]
            (column []
                [ viewTheme model.theme
                , viewComponents model
                , viewDiffTest model.theme
                ]
            )
        ]


viewComponents : Components -> Element Msg
viewComponents c =
    el [ padding 20 ]
        (column [ spacing 40 ]
            [ viewComponent "Tabs"
                none
                (text (Debug.toString c.activeTab))
                (TabsComponent.view c.theme
                    { tabs =
                        Array.fromList
                            [ { name = "Tab 1"
                              , content = text "Content 1"
                              }
                            , { name = "Tab 2"
                              , content = text "Content 2"
                              }
                            ]
                    , onSwitchTab = SwitchTab
                    , activeTab = c.activeTab
                    }
                )
            , viewComponent "Drill-down Panel"
                none
                (text (Debug.toString c.drillDownIsOpen))
                (DrillDownPanel.drillDownPanel c.theme
                    { openMsg = OpenDrillDown
                    , closeMsg = CloseDrillDown
                    , depth = 1
                    , closedElement = text "Header"
                    , openHeader = text "Header"
                    , openElement = text "Detail"
                    , isOpen = c.drillDownIsOpen
                    , zIndex = 9999
                    }
                )
            , viewComponent "Picklist"
                (text (Debug.toString c.picklist))
                none
                (Picklist.view c.theme
                    { state = c.picklist
                    , onStateChange = PicklistChanged
                    }
                    [ ( 1, text "Option A" )
                    , ( 2, text "Option B" )
                    , ( 3, text "Option C" )
                    , ( 4, text "Option D" )
                    , ( 5, text "Option E" )
                    , ( 6, text "Option F" )
                    , ( 7, text "Option G" )
                    ]
                )
            ]
        )


viewComponent : String -> Element msg -> Element msg -> Element msg -> Element msg
viewComponent title internalState externalState component =
    column [ spacing 20 ]
        [ el [ Font.size 24 ] (text title)
        , column [ paddingEach { top = 0, right = 0, bottom = 0, left = 20 }, spacing 20 ]
            [ row [ spacing 10 ] [ text "Internal State:", internalState ]
            , row [ spacing 10 ] [ text "External State:", externalState ]
            , el
                [ padding 20
                , Background.color (rgb 0.9 0.9 0.9)
                ]
                component
            ]
        ]


viewTheme : Theme -> Element Msg
viewTheme theme =
    column [ padding 20, spacing 20 ]
        [ row [ spacing 20 ]
            [ row [ spacing 10 ]
                [ text "Font size:"
                , text (String.fromInt theme.fontSize)
                , Input.button []
                    { onPress = Just IncreaseFontSize
                    , label = el [ padding 4 ] (text "+")
                    }
                , Input.button []
                    { onPress = Just DecreaseFontSize
                    , label = el [ padding 4 ] (text "-")
                    }
                ]
            , row [ spacing 10 ] [ text "Colors:" ]
            , viewColors theme.colors
            ]
        ]


viewColors : Colors -> Element Msg
viewColors colors =
    let
        highlight =
            rgb 1 0 0
    in
    row [ spacing 4 ]
        ([ ( colors.lightest, \c -> { c | lightest = highlight }, "lightest" )
         , ( colors.darkest, \c -> { c | darkest = highlight }, "darkest" )
         , ( colors.primaryHighlight, \c -> { c | primaryHighlight = highlight }, "primaryHighlight" )
         , ( colors.secondaryHighlight, \c -> { c | secondaryHighlight = highlight }, "secondaryHighlight" )
         , ( colors.positive, \c -> { c | positive = highlight }, "positive" )
         , ( colors.positiveLight, \c -> { c | positiveLight = highlight }, "positiveLight" )
         , ( colors.negative, \c -> { c | negative = highlight }, "negative" )
         , ( colors.negativeLight, \c -> { c | negativeLight = highlight }, "negativeLight" )
         , ( colors.backgroundColor, \c -> { c | backgroundColor = highlight }, "backgroundColor" )
         , ( colors.selectionColor, \c -> { c | selectionColor = highlight }, "selectionColor" )
         , ( colors.secondaryInformation, \c -> { c | secondaryInformation = highlight }, "secondaryInformation" )
         , ( colors.gray, \c -> { c | gray = highlight }, "gray" )
         ]
            |> List.map
                (\( color, updateColors, name ) ->
                    row
                        [ spacing 10
                        , Events.onClick (HighlightColor updateColors)
                        ]
                        [ el
                            [ width (px 16)
                            , height (px 16)
                            , Background.color color
                            , Border.width 1
                            , htmlAttribute (Html.Attributes.title name)
                            ]
                            none

                        --, text name
                        ]
                )
        )


viewDiffTest : Theme -> Element msg
viewDiffTest theme =
    let
        viewDiffRow : Value ta va -> Value ta va -> Element msg
        viewDiffRow a b =
            column [ Element.spacing <| Theme.smallSpacing theme ]
                [ row []
                    [ el [ Font.bold ] (text <| "Value A: ")
                    , text (Value.toString a)
                    ]
                , row []
                    [ el [ Font.bold ] (text <| "Value B: ")
                    , text (Value.toString b)
                    ]
                , row [] [ text "Difference: ", viewValueDifference theme a b ]
                ]

        stringA =
            Value.Literal () (StringLiteral "MSBuys")

        stringB =
            Value.Literal () (StringLiteral "MSSells")

        intA =
            Value.Literal () (WholeNumberLiteral 86)

        intB =
            Value.Literal () (WholeNumberLiteral 33)

        floatA =
            Value.Literal () (FloatLiteral 5.5)

        floatB =
            Value.Literal () (FloatLiteral 10.5)

        decimalA =
            Value.Literal () (DecimalLiteral (Decimal.fromFloat 5.1))

        decimalB =
            Value.Literal () (DecimalLiteral (Decimal.fromFloat 99.33))

        listA =
            Value.List () [ intA, floatA, decimalA, decimalB ]

        listB =
            Value.List () [ intA, floatA, decimalB, intB ]

        recordA =
            Value.record ()
                (Dict.fromList [ ( Name.fromString "position", stringA ), ( Name.fromString "amount", decimalA ) ])

        recordB =
            Value.record ()
                (Dict.fromList [ ( Name.fromString "position", stringB ), ( Name.fromString "id", intA ), ( Name.fromString "value", decimalB ) ])

        dictA =
            Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "from", "list" ] )) (Value.List () [ Value.Tuple () [ stringA, floatA ], Value.Tuple () [ stringB, floatB ] ])

        dictB =
            Value.Apply () (Value.Reference () ( [ [ "morphir" ], [ "s", "d", "k" ] ], [ [ "dict" ] ], [ "from", "list" ] )) (Value.List () [ Value.Tuple () [ stringB, floatA ] ])
    in
    Element.column [ spacing <| Theme.largeSpacing theme ]
        [ viewDiffRow stringA stringB
        , viewDiffRow intA intB
        , viewDiffRow floatA floatB
        --, viewDiffRow decimalA decimalB
        , viewDiffRow listA listB
        , viewDiffRow recordA recordB
        , viewDiffRow dictA dictB
        , viewDiffRow (LocalDate.fromISO () (Value.Literal () (StringLiteral "1999-01-02"))) (LocalDate.fromISO () (Value.Literal () (StringLiteral "2000-01-01")))
        ]
