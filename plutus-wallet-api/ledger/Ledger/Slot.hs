{-# LANGUAGE FlexibleContexts     #-}
{-# LANGUAGE DerivingStrategies   #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE DeriveGeneric        #-}
{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE DeriveAnyClass       #-}
{-# LANGUAGE MonoLocalBinds       #-}
-- | Slots and slot ranges.
module Ledger.Slot(
      Slot(..)
    , SlotRange
    , singleton
    , Ledger.Slot.eq
    , empty
    , member
    , width
    , contains
    , before
    , after
    ) where

import           Codec.Serialise.Class                    (Serialise)
import           Data.Aeson                               (FromJSON, ToJSON)
import           Data.Swagger.Internal.Schema             (ToSchema)
import           GHC.Generics                             (Generic)
import           Language.Haskell.TH

import           Language.PlutusTx.Lift                   (makeLift)
import           Language.PlutusTx.Prelude                as P

import           Ledger.Interval

-- | The slot number. This is a good proxy for time, since on the Cardano blockchain
-- slots pass at a constant rate.
newtype Slot = Slot { getSlot :: Int }
    deriving (Eq, Ord, Show, Enum)
    deriving stock (Generic)
    deriving anyclass (ToSchema, FromJSON, ToJSON)
    deriving newtype (Num, Real, Integral, Serialise)

makeLift ''Slot

-- | An 'Interval' of 'Slot's.
type SlotRange = Interval Slot

-- | A 'SlotRange' that covers only a single slot.
singleton :: Q (TExp (Slot -> SlotRange))
singleton = [|| \(Slot s) -> Interval (Just (Slot s)) (Just (Slot ($$plus s 1))) ||]

-- | Equality of 'Slot' values
eq :: Q (TExp (Slot -> Slot -> Bool))
eq = [|| \(Slot s) (Slot s') -> $$(P.eq) s s' ||]

-- | Check if a 'SlotRange' is empty.
empty :: Q (TExp (SlotRange -> Bool))
empty = [||
    \(Interval f t) ->
        case f of
            Nothing -> False
            Just (Slot f') -> case t of
                Nothing -> False
                Just (Slot t') -> $$geq f' t'
    ||]

-- | Check if 'Slot' is contained in a 'SlotRange'.
member :: Q (TExp (Slot -> SlotRange -> Bool))
member = [||
    \(Slot s) (Interval f t) ->
        let lw = case f of { Nothing -> True; Just (Slot f') -> $$leq f' s; }
            hg = case t of { Nothing -> True; Just (Slot t') -> $$gt t' s; }
        in
            if lw then hg else False
    ||]

-- | Number of 'Slot's covered by the interval. @width (from x) == Nothing@.
width :: Q (TExp (SlotRange -> Maybe Int))
width = [||
    \(Interval f t) ->
        case f of
            Nothing -> Nothing
            Just (Slot f') -> case t of
                Nothing -> Nothing
                Just (Slot t') -> Just ($$minus t' f')  ||]

-- | @a `contains` b@ is true if the 'SlotRange' @b@ is entirely contained in
--   @a@. That is, @a `contains` b@ if for every slot @s@, if @member s b@ then
--   @member s a@.
contains :: Q (TExp (SlotRange -> SlotRange -> Bool))
contains = [||
    \(Interval af at) (Interval bf bt) ->
        let lw = case af of
                Nothing -> True
                Just (Slot af') -> case bf of
                    Nothing -> False
                    Just (Slot bf') -> $$leq af' bf'
            hg = case at of
                Nothing -> True
                Just (Slot at') -> case bt of
                    Nothing -> False
                    Just (Slot bt') -> $$geq at' bt'
        in
            if lw then hg else False
    ||]

-- | Check if a 'Slot' is earlier than the beginning of a 'SlotRange'.
before :: Q (TExp (Slot -> SlotRange -> Bool))
before = [||
    \(Slot h) (Interval f _) -> case f of { Nothing -> False; Just (Slot h') -> $$gt h' h; }
    ||]

-- | Check if a 'Slot' is later than the end of a 'SlotRange'
after :: Q (TExp (Slot -> SlotRange -> Bool))
after = [||
    \(Slot h) (Interval _ t) -> case t of { Nothing -> False; Just (Slot t') -> $$geq h t'; }
    ||]
