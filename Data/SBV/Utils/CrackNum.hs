-----------------------------------------------------------------------------
-- |
-- Module    : Data.SBV.Utils.CrackNum
-- Copyright : (c) Levent Erkok
-- License   : BSD3
-- Maintainer: erkokl@gmail.com
-- Stability : experimental
--
-- Crack internal representation for numeric types
-----------------------------------------------------------------------------

{-# LANGUAGE NamedFieldPuns #-}

{-# OPTIONS_GHC -Wall -Werror #-}

module Data.SBV.Utils.CrackNum (
        crackNum
      ) where

import Data.SBV.Core.Concrete
import Data.SBV.Core.Kind
import Data.SBV.Core.SizedFloats
import Data.SBV.Utils.Numeric
import Data.SBV.Utils.PrettyNum (showFloatAtBase)

import Data.Char (intToDigit, toUpper, isSpace)

import Data.Bits
import Data.List

import LibBF hiding (Zero, bfToString)

import Numeric

-- | A class for cracking things deeper, if we know how.
class CrackNum a where
  crackNum :: a -> Maybe String

instance CrackNum CV where
  crackNum cv = case kindOf cv of
                  -- Maybe one day we'll have a use for these, currently cracking them
                  -- any further seems overkill
                  KBool      {}  -> Nothing
                  KUnbounded {}  -> Nothing
                  KReal      {}  -> Nothing
                  KUserSort  {}  -> Nothing
                  KChar      {}  -> Nothing
                  KString    {}  -> Nothing
                  KList      {}  -> Nothing
                  KSet       {}  -> Nothing
                  KTuple     {}  -> Nothing
                  KMaybe     {}  -> Nothing
                  KEither    {}  -> Nothing

                  -- Actual crackables
                  KFloat{}       -> Just $ let CFloat   f = cvVal cv in float f
                  KDouble{}      -> Just $ let CDouble  d = cvVal cv in float d
                  KFP{}          -> Just $ let CFP      f = cvVal cv in float f
                  KBounded sg sz -> Just $ let CInteger i = cvVal cv in int   sg sz i

-- How far off the screen we want displayed? Somewhat experimentally found.
tab :: String
tab = replicate 18 ' '

-- Make splits of 4, top one has the remainder
split4 :: Int -> [Int]
split4 n
  | m == 0 =     rest
  | True   = m : rest
  where (d, m) = n `divMod` 4
        rest   = replicate d 4

-- Convert bits to the corresponding integer.
getVal :: [Bool] -> Integer
getVal = foldl (\s b -> 2 * s + if b then 1 else 0) 0

-- Show in hex, but pay attention to how wide a field it should be in
mkHex :: [Bool] -> String
mkHex bin = map toUpper $ showHex (getVal bin) ""

-- | Show a sized word/int in detail
int :: Bool -> Int -> Integer -> String
int signed sz v = intercalate "\n" $ ruler ++ info
  where splits = split4 sz

        ruler = map (tab ++) $ mkRuler sz splits

        bitRep :: [[Bool]]
        bitRep = split splits [v `testBit` i | i <- reverse [0 .. sz - 1]]

        flatHex = concatMap mkHex bitRep
        iprec
          | signed = "Signed "   ++ show sz ++ "-bit 2's complement integer"
          | True   = "Unsigned " ++ show sz ++ "-bit word"

        signBit = v `testBit` (sz-1)
        s | signBit = "-"
          | True    = ""

        av = abs v

        info = [ "   Binary layout: " ++ unwords [concatMap (\b -> if b then "1" else "0") is | is <- bitRep]
               , "      Hex layout: " ++ unwords (split (split4 (length flatHex)) flatHex)
               , "            Type: " ++ iprec
               ]
            ++ [ "            Sign: " ++ if signBit then "Negative" else "Positive" | signed]
            ++ [ "    Binary Value: " ++ s ++ "0b" ++ showIntAtBase 2 intToDigit av ""
               , "     Octal Value: " ++ s ++ "0o" ++ showOct av ""
               , "   Decimal Value: " ++ show v
               , "       Hex Value: " ++ s ++ "0x" ++ showHex av ""
               ]

-- | What kind of Float is this?
data FPKind = Zero       Bool  -- with sign
            | Infty      Bool  -- with sign
            | NaN
            | Subnormal
            | Normal
            deriving Eq

-- | Show instance for Kind, not for reading back!
instance Show FPKind where
  show Zero{}    = "FP_ZERO"
  show Infty{}   = "FP_INFINITE"
  show NaN       = "FP_NAN"
  show Subnormal = "FP_SUBNORMAL"
  show Normal    = "FP_NORMAL"

-- | Find out what kind this float is. We specifically ask
-- the caller to provide if the number is zero, neg-inf, and pos-inf. Why?
-- Because the FP type doesn't have those recognizers that also work with Float/Double.
getKind :: RealFloat a => a -> FPKind
getKind fp
 | fp == 0           = Zero  (isNegativeZero fp)
 | isInfinite fp     = Infty (fp < 0)
 | isNaN fp          = NaN
 | isDenormalized fp = Subnormal
 | True              = Normal

-- Show the value in different bases
showAtBases :: FPKind -> (String, String, String, String) -> Either String (String, String, String, String)
showAtBases k bvs = case k of
                     Zero False  -> Right ("0b0.0",  "0o0.0",  "0.0",  "0x0.0")
                     Zero True   -> Right ("-0b0.0", "-0o0.0", "-0.0", "-0x0.0")
                     Infty False -> Left  "Infinity"
                     Infty True  -> Left  "-Infinity"
                     NaN         -> Left  "NaN"
                     Subnormal   -> Right bvs
                     Normal      -> Right bvs

-- | Float data for display purposes
data FloatData = FloatData { prec   :: String
                           , eb     :: Int
                           , sb     :: Int
                           , bits   :: Integer
                           , fpKind :: FPKind
                           , fpVals :: Either String (String, String, String, String)
                           }

-- | A simple means to organize different bits and pieces of float data
-- for display purposes
class HasFloatData a where
  getFloatData :: a -> FloatData

-- | Float instance
instance HasFloatData Float where
  getFloatData f = FloatData {
      prec   = "Single"
    , eb     =  8
    , sb     = 24
    , bits   = fromIntegral (floatToWord f)
    , fpKind = k
    , fpVals = showAtBases k (showFloatAtBase 2 f "", showFloatAtBase 8 f "", showFloatAtBase 10 f "", showFloatAtBase 16 f "")
    }
    where k = getKind f

-- | Double instance
instance HasFloatData Double where
  getFloatData d  = FloatData {
      prec   = "Double"
    , eb     = 11
    , sb     = 53
    , bits   = fromIntegral (doubleToWord d)
    , fpKind = k
    , fpVals = showAtBases k (showFloatAtBase 2 d "", showFloatAtBase 8 d "", showFloatAtBase 10 d "", showFloatAtBase 16 d "")
    }
    where k = getKind d

-- | Find the exponent values, (exponent value, exponent as stored, bias)
getExponentData :: FloatData -> (Integer, Integer, Integer)
getExponentData FloatData{eb, sb, bits, fpKind} = (expValue, expStored, bias)
  where -- | Bias is 2^(eb-1) - 1
        bias :: Integer
        bias = (2 :: Integer) ^ ((fromIntegral eb :: Integer) - 1) - 1

        -- | Exponent as stored is simply bit extraction
        expStored = getVal [bits `testBit` i | i <- reverse [sb-1 .. sb+eb-2]]

        -- | Exponent value is stored exponent - bias, unless the number is subnormal. In that case it is 1 - bias
        expValue = case fpKind of
                     Subnormal -> 1 - bias
                     _         -> expStored - bias

-- | FP instance
instance HasFloatData FP where
  getFloatData v@(FP eb sb f) = FloatData {
      prec   = case (eb, sb) of
                 ( 5,  11) -> "Half (5 exponent bits, 10 significand bits.)"
                 ( 8,  24) -> "Single (8 exponent bits, 23 significand bits.)"
                 (11,  53) -> "Double (11 exponent bits, 52 significand bits.)"
                 (15, 113) -> "Quad (15 exponent bits, 112 significand bits.)"
                 ( _,   _) -> show eb ++ " exponent bits, " ++ show (sb-1) ++ " significand bit" ++ if sb > 2 then "s" else ""
    , eb     = eb
    , sb     = sb
    , bits   = bfToBits (mkBFOpts eb sb NearEven) f
    , fpKind = k
    , fpVals = showAtBases k (bfToString 2 True v, bfToString 8 True v, bfToString 10 True v, bfToString 16 True v)
    }
    where opts = mkBFOpts eb sb NearEven
          k | bfIsZero f           = Zero  (bfIsNeg f)
            | bfIsInf f            = Infty (bfIsNeg f)
            | bfIsNaN f            = NaN
            | bfIsSubnormal opts f = Subnormal
            | True                 = Normal

-- | Show a float in detail
float :: HasFloatData a => a -> String
float f = intercalate "\n" $ ruler ++ legend : info
   where fd@FloatData{prec, eb, sb, bits, fpKind, fpVals} = getFloatData f

         splits = [1, eb, sb]
         ruler  = map (tab ++) $ mkRuler (eb + sb) splits

         legend = tab ++ "S " ++ mkTag ('E' : show eb) eb ++ " " ++ mkTag ('S' : show (sb-1)) (sb-1)

         mkTag t len = take len $ replicate ((len - length t) `div` 2) '-' ++ t ++ repeat '-'

         allBits :: [Bool]
         allBits = [bits `testBit` i | i <- reverse [0 .. eb + sb - 1]]

         flatHex = concatMap mkHex (split (split4 (eb + sb)) allBits)
         sign    = bits `testBit` (eb+sb-1)

         (exponentVal, storedExponent, bias) = getExponentData fd

         esInfo = "Stored: " ++ show storedExponent ++ ", Bias: " ++ show bias

         isSubNormal = case fpKind of
                         Subnormal -> True
                         _         -> False

         info =   [ "   Binary layout: " ++ unwords [concatMap (\b -> if b then "1" else "0") is | is <- split splits allBits]
                  , "      Hex layout: " ++ unwords (split (split4 (length flatHex)) flatHex)
                  , "       Precision: " ++ prec
                  , "            Sign: " ++ if sign then "Negative" else "Positive"
                  ]
               ++ [ "        Exponent: " ++ show exponentVal ++ " (Subnormal, with fixed exponent value. " ++ esInfo ++ ")" | isSubNormal    ]
               ++ [ "        Exponent: " ++ show exponentVal ++ " ("                                       ++ esInfo ++ ")" | not isSubNormal]
               ++ [ "  Classification: " ++ show fpKind]
               ++ (case fpVals of
                     Left val                       -> [ "           Value: " ++ val]
                     Right (bval, oval, dval, hval) -> [ "    Binary Value: " ++ bval
                                                       , "     Octal Value: " ++ oval
                                                       , "   Decimal Value: " ++ dval
                                                       , "       Hex Value: " ++ hval
                                                       ])
               ++ [ "            Note: Representation for NaN's is not unique" | fpKind == NaN]


-- | Build a ruler with given split points
mkRuler :: Int -> [Int] -> [String]
mkRuler n splits = map (trimRight . unwords . split splits . trim Nothing) $ transpose $ map pad $ reverse [0 .. n-1]
  where len = length (show (n-1))
        pad i = reverse $ take len $ reverse (show i) ++ repeat '0'

        trim _      "" = ""
        trim mbPrev (c:cs)
          | mbPrev == Just c = ' ' : trim mbPrev   cs
          | True             =  c  : trim (Just c) cs

        trimRight = reverse . dropWhile isSpace . reverse

split :: [Int] -> [a] -> [[a]]
split _      [] = []
split []     xs = [xs]
split (i:is) xs = case splitAt i xs of
                   (pre, [])   -> [pre]
                   (pre, post) -> pre : split is post
