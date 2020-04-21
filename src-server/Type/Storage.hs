{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE OverloadedStrings #-}

module Type.Storage
    ( HashEBSD(..)
    , HashOR(..)
    , HashArche(..)
    , StorageBucket(bktText)
    , voxelBucket
    , facesBucket
    , edgesBucket
    , vertexBucket
    , ebsdBucket
    ) where

import Control.Lens ((&), (^.), (^?), (?~), (.~), ix, set)
import GHC.Generics
import Data.Aeson    (ToJSON, FromJSON)
import Data.Hashable (Hashable, hashWithSalt)
import Data.Text     (Text)
import Servant       (FromHttpApiData(..))

import qualified Network.Google.FireStore as FireStore

import Util.FireStore

newtype HashEBSD  = HashEBSD  Text deriving (Show, Generic, Eq)
newtype HashOR    = HashOR    Text deriving (Show, Generic, Eq)
newtype HashArche = HashArche Text deriving (Show, Generic, Eq)

newtype StorageBucket = StorageBucket {bktText :: Text} deriving (Show, Generic, Eq)

voxelBucket :: StorageBucket
voxelBucket  = StorageBucket "voxel"

facesBucket :: StorageBucket
facesBucket  = StorageBucket "faces"

edgesBucket :: StorageBucket
edgesBucket  = StorageBucket "edges"

vertexBucket :: StorageBucket
vertexBucket = StorageBucket "vertex"

ebsdBucket :: StorageBucket
ebsdBucket = StorageBucket "ebsd"

-- ============================
-- ======== Instances =========
-- ============================

-- ========= Document =========
instance ToDocValue HashEBSD where
    toValue (HashEBSD txt) = FireStore.value & FireStore.vStringValue ?~ txt

-- ========= FromHttp =========
instance FromHttpApiData HashEBSD where
    parseUrlPiece txt = Right $ HashEBSD txt

instance FromHttpApiData HashOR where
    parseUrlPiece txt = Right $ HashOR txt

instance FromHttpApiData HashArche where
    parseUrlPiece txt = Right $ HashArche txt

-- ========= JSON =========
instance ToJSON HashEBSD
instance FromJSON HashEBSD

instance ToJSON HashOR
instance FromJSON HashOR

instance ToJSON HashArche
instance FromJSON HashArche

instance ToJSON StorageBucket
instance FromJSON StorageBucket