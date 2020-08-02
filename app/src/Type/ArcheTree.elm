module Type.ArcheTree exposing (..)

import Array exposing (Array)

import Type.FocusedList exposing (FocusedList)
import Type.FocusedList as FocusedList
import Type.Arche exposing (Arche)
import Type.EBSD exposing (EBSD)
import Type.OR exposing (OREval)


type alias EbsdHash = String
type alias OrHash = String

type alias EBSDNode =
    { ebsd: EBSD
    , ors: FocusedList ORNode
    } 

type alias ORNode =
    { orEvaluation: OREval
    , arches: FocusedList ArcheNode
    } 

type alias ArcheNode =
    { archeResult: Arche
    } 

type alias ArcheTree = FocusedList EBSDNode

empty : ArcheTree
empty = FocusedList.fromArray Array.empty (\e -> e.ebsd.hashEBSD)

refreshArcheTree : ArcheTree -> Array EBSD -> ArcheTree
refreshArcheTree at les =
    let
        newORNode = FocusedList.fromArray Array.empty (\o -> o.orEvaluation.hashOR)
        nodes = Array.map (\x -> {ebsd = x, ors = newORNode}) les
    in FocusedList.mergeNew at nodes 

refreshORNode : FocusedList ORNode -> Array OREval -> FocusedList ORNode
refreshORNode at les =
    let
        newArcheNode = FocusedList.fromArray Array.empty (\o -> o.archeResult.hashArche)
        nodes = Array.map (\x -> {orEvaluation = x, arches = newArcheNode}) les
    in FocusedList.mergeNew at nodes 

refreshArcheNode : FocusedList ArcheNode -> Array Arche -> FocusedList ArcheNode
refreshArcheNode at les =
    let
        nodes = Array.map (\x -> {archeResult = x}) les
    in FocusedList.mergeNew at nodes 

refreshOR : ArcheTree -> EbsdHash -> Array OREval -> ArcheTree
refreshOR at hash lor = case FocusedList.find at hash of 
    Nothing -> at
    Just node ->
        let
            newNode = {node | ors = refreshORNode node.ors lor}
        in FocusedList.update at newNode

refreshArche : ArcheTree -> EbsdHash -> OrHash -> Array Arche -> ArcheTree
refreshArche at hashE hashO lor = case FocusedList.find at hashE of 
    Nothing -> at
    Just nodeO -> case FocusedList.find nodeO.ors hashO of
        Just nodeE ->
            let
                newNodeE = {nodeE | arches = refreshArcheNode nodeE.arches lor}
            in FocusedList.update at {nodeO | ors = FocusedList.update nodeO.ors newNodeE}
        Nothing -> at

listEBSDWithFocus : ArcheTree -> (EBSD -> Bool -> b) -> List b 
listEBSDWithFocus at foo = FocusedList.listWithFocus at (\a b -> foo a.ebsd b)

listORWithFocus : ArcheTree -> (OREval -> Bool -> b) -> List b 
listORWithFocus at foo = case FocusedList.getFocus at of
    Nothing   -> []
    Just ebsd -> FocusedList.listWithFocus ebsd.ors (\a b -> foo a.orEvaluation b)

getEBSDFocusKey : ArcheTree -> Maybe String
getEBSDFocusKey = FocusedList.getFocusKey

getORFocusKey : ArcheTree -> Maybe String
getORFocusKey at = Maybe.andThen (\x -> FocusedList.getFocusKey x.ors) (FocusedList.getFocus at)

focusOnEbsd : ArcheTree -> String -> ArcheTree
focusOnEbsd = FocusedList.focusOn

focusOnOR : ArcheTree -> String -> ArcheTree
focusOnOR at key = case FocusedList.getFocus at of 
    Nothing -> at
    Just focusedEBSD -> FocusedList.update at {focusedEBSD | ors = FocusedList.focusOn focusedEBSD.ors key}