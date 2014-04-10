{-# LANGUAGE RecordWildCards            #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE ExistentialQuantification  #-}

module Gamma.GammaFinder
       ( findGamma
       , findGamma2
       , findOR
       , getGamma
       , getGammaOR
       , getGammaOR2
       , OR (..)
       , ksORs
       , ksOR
       , testGammaFit
       , testFindGamma
       , testMisFunc
       ) where

import qualified Data.Vector         as V
import qualified Data.Vector.Unboxed as U
import qualified Data.Vector.Generic as G
import qualified Data.Packed         as HV

import qualified Data.Vector.Generic.Base    as GB
import qualified Data.Vector.Generic.Mutable as GM

import           Numeric.Container   (add, sub)
import           Data.Vector.Unboxed (Vector)
import           System.Random       (randomIO)

import           Numeric.GSL.Minimization
import           File.ANGReader
import           Texture.Orientation
import           Texture.Symmetry

import           Hammer.Math.Algebra
import           Hammer.Math.Optimum

import           Gamma.KurdjumovSachs

import           Debug.Trace
import           Hammer.VTK
import           Texture.SH.HyperSphere

dbg a = trace (show a) a

newtype FZ = FZ {qFZ :: Quaternion} deriving (Show, GB.Vector U.Vector, GM.MVector U.MVector, U.Unbox)
newtype OR = OR {qOR :: Quaternion} deriving (Show, GB.Vector U.Vector, GM.MVector U.MVector, U.Unbox)

getQinFZ :: Quaternion -> FZ
getQinFZ = FZ . toFZ Cubic

ksOR :: OR
ksOR = OR $ toQuaternion $ mkAxisPair (Vec3 1 1 2) (Deg 90)

ksORs :: Vector OR
ksORs = genTS ksOR

genTS :: OR -> Vector OR
genTS (OR t) = let
  (w, v) = splitQuaternion t
  vs = V.convert $ getAllSymmVec (getSymmOps Cubic) v
  in G.map (OR . mergeQuaternion . ((,) w)) vs

getGammaOR2 :: EBSDdata -> (Quaternion, OR)
getGammaOR2 EBSDdata{..} = trace (show (testGammaFit gf qs tf)) (gf, tf)
  where
    is = U.convert $ V.findIndices ((> 0.1) . ci) nodes
    qs = G.map (rotation . (nodes G.!)) is
    (gf, tf) = findGamma2 qs

getGammaOR :: Int -> EBSDdata -> (Quaternion, OR)
getGammaOR n EBSDdata{..} = go n t0
  where
    t0 = mkOR (Vec3 1 1 2) (Deg 90)
    is = V.convert $ V.findIndices ((> 0.1) . ci) nodes
    qs = G.map (rotation . (nodes G.!)) is
    func t = let
      g = findGamma (genTS t) qs
      in trace (show (testGammaFit g qs t)) $ findOR g qs t
    go k t
      | k <= 0    = (findGamma (genTS t) qs, convert t)
      | otherwise = go (k-1) (func t)

getGamma :: EBSDdata -> Quaternion
getGamma EBSDdata{..} = let
  t0 = mkOR (Vec3 1 1 2) (Deg 90)
  ts = genTS t0
  is = V.convert $ V.findIndices ((> 0.1) . ci) nodes
  qs = G.map (rotation . (nodes G.!)) is
  gamma = toFZ Cubic $ findGamma ts qs
  in trace (show $ testGammaFit gamma qs t0) gamma

findOR :: Quaternion -> Vector Quaternion  -> OR -> OR
findOR ga qs t0 = let
  fzqs = G.map getQinFZ qs
  func v = let
    t = OR . toQuaternion $ mkUnsafeRodrigues v
    in errorfunc ga (genTS t) fzqs
  foo v = let
    k  = 0.001
    x  = func v
    d1 = (func (v &+ Vec3 k 0 0) - func (v &- Vec3 k 0 0)) / (2*k)
    d2 = (func (v &+ Vec3 0 k 0) - func (v &- Vec3 0 k 0)) / (2*k)
    d3 = (func (v &+ Vec3 0 0 k) - func (v &- Vec3 0 0 k)) / (2*k)
    in (x, Vec3 d1 d2 d3)
  guess = rodriVec $ fromQuaternion $ qOR t0
  in OR $ toQuaternion $ mkUnsafeRodrigues $ bfgs defaultBFGS foo guess

findGamma :: Vector OR -> Vector Quaternion -> Quaternion
findGamma ts qs = let
  fzqs = G.map getQinFZ qs
  func v = let
    gamma = toQuaternion $ mkUnsafeRodrigues v
    in errorfunc gamma ts fzqs
  foo v = let
    k  = 0.001
    x  = func v
    d1 = (func (v &+ Vec3 k 0 0) - func (v &- Vec3 k 0 0)) / (2*k)
    d2 = (func (v &+ Vec3 0 k 0) - func (v &- Vec3 0 k 0)) / (2*k)
    d3 = (func (v &+ Vec3 0 0 k) - func (v &- Vec3 0 0 k)) / (2*k)
    in (x, Vec3 d1 d2 d3)
  guess = rodriVec $ fromQuaternion $ hotStart fzqs
  cfg   = BFGScfg { epsi = 1e-4, tol = 1e-4, niter = 200 }
  in toQuaternion $ mkUnsafeRodrigues $ bfgs cfg foo guess

findGamma2 :: Vector Quaternion -> (Quaternion, OR)
findGamma2 qs = let
  fzqs = G.map getQinFZ qs
  func v = let
    [x1,x2,x3, k1, k2, k3] = HV.toList v
    g = toQuaternion $ mkUnsafeRodrigues (Vec3 x1 x2 x3)
    t = OR $ toQuaternion $ mkUnsafeRodrigues (Vec3 k1 k2 k3)
    in errorfunc g (genTS t) fzqs
  foo v = let
    d1 = HV.fromList [k, 0, 0, 0, 0, 0]
    d2 = HV.fromList [0, k, 0, 0, 0, 0]
    d3 = HV.fromList [0, 0, k, 0, 0, 0]
    d4 = HV.fromList [0, 0, 0, k, 0, 0]
    d5 = HV.fromList [0, 0, 0, 0, k, 0]
    d6 = HV.fromList [0, 0, 0, 0, 0, k]
    k  = 0.001
    dr1 = (func (v `add` d1) - func (v `sub` d1)) / (2*k)
    dr2 = (func (v `add` d2) - func (v `sub` d2)) / (2*k)
    dr3 = (func (v `add` d3) - func (v `sub` d3)) / (2*k)

    dt1 = (func (v `add` d4) - func (v `sub` d4)) / (2*k)
    dt2 = (func (v `add` d5) - func (v `sub` d5)) / (2*k)
    dt3 = (func (v `add` d6) - func (v `sub` d6)) / (2*k)
    in (HV.fromList [dr1, dr2, dr3, dt1, dt2, dt3])
  Vec3 ra rb rc = rodriVec $ convert $ hotStart fzqs
  Vec3 ta tb tc = rodriVec $ convert $ qOR $ mkOR (Vec3 1 1 2) (Deg 90)
  guess = HV.fromList [ra, rb, rc, ta, tb, tc]
  (r,_) = minimizeVD VectorBFGS2 0.00001 200 0.01 0.1 func foo guess
  --box = HV.fromList [5,5,5,5,5,5]
  --(r,_) = minimizeV NMSimplex2	0.00001 200 box func guess
  [r1, r2, r3, t1, t2, t3] = HV.toList r
  gf = convert $ mkUnsafeRodrigues (Vec3 r1 r2 r3)
  tf = convert $ mkUnsafeRodrigues (Vec3 t1 t2 t3)
  in (gf, tf)

hotStart :: Vector FZ -> Quaternion
hotStart gms = let
  qs = V.fromList $
       [ toQuaternion (mkEuler (Deg phi1) (Deg phi) (Deg phi2))
       | phi1 <- [0.0, 3 .. 90]
       , phi  <- [0.0, 3 .. 90]
       , phi2 <- [0.0, 3 .. 90]
       ]
  func q = errorfunc q ksORs gms
  i = V.minIndex $ V.map func qs
  in qs V.! i

hotStartOR :: Quaternion -> Vector FZ -> OR
hotStartOR q gms = let
  ks   = rodriVec $ fromQuaternion $ toQuaternion $ mkAxisPair (Vec3 1 1 2) (Deg 90)
  func = OR . toQuaternion . mkUnsafeRodrigues . (ks &+)
  ts = V.fromList $
       [ func (Vec3 r1 r2 r3)
       | r1 <- [-0.2, 0.02 .. 0.2]
       , r2 <- [-0.2, 0.02 .. 0.2]
       , r3 <- [-0.2, 0.02 .. 0.2]
       ]
  foo t = errorfunc q (genTS t) gms
  i = V.minIndex $ V.map foo ts
  in ts V.! i

errorfunc :: Quaternion-> Vector OR -> Vector FZ -> Double
errorfunc ga ts gms1FZ = abs $ 1 - (total / n)
  where
    func gm1 gm2 = abs $ composeQ0 (invert gm2) (qFZ gm1)

    gms2   = G.map (toFZ Cubic . (ga #<=) . qOR) ts
    q0s    = G.map (\gm1 -> G.maximum $ G.map (func gm1) gms2) gms1FZ

    total = G.sum q0s
    n     = fromIntegral (G.length gms1FZ)

instance Rot OR where
  (OR p) #<= (OR q) = OR $ p #<= q
  invert         = OR . invert . qOR
  toQuaternion   = qOR
  fromQuaternion = OR
  zerorot        = OR zerorot
  getOmega       = getOmega . qOR

mkOR :: Vec3 -> Deg -> OR
mkOR v = OR . toQuaternion . mkAxisPair v

convert :: (Rot a, Rot b) => a -> b
convert = fromQuaternion . toQuaternion

-- ================================= Test Function =======================================

testGammaFit :: Quaternion -> Vector Quaternion -> OR -> (Double, Double)
testGammaFit ga gs t = let
  gms = G.map getQinFZ gs
  m1  = errorfunc ga (genTS t) gms
  m2  = errorfuncSlowButSure ga gs (qOR t)
  in (m1, m2)

testMisFunc :: IO ()
testMisFunc = do
  a <- randomIO
  let gms = G.map (getQinFZ . (a #<=) . toQuaternion) ksORs
  print $ errorfuncSlowButSure a (G.map qFZ gms) (qOR ksOR)
  print $ errorfunc a ksORs gms

testFindOR :: IO ()
testFindOR = do
  a <- randomIO
  let
    t  = mkOR (Vec3 1 1 2) (Deg 90)
    ts = genTS t
    ms = G.map ((a #<=) . qOR) ts
    t' = findOR a ms t
    fzqs = G.map getQinFZ ms
  print (convert t  :: AxisPair)
  print (convert t' :: AxisPair)
  print ((convert $ hotStartOR a fzqs) :: AxisPair)

testFindGamma :: IO ()
testFindGamma = randomIO >>= plotErrFunc

plotErrFunc :: Quaternion -> IO ()
plotErrFunc a = let
  gms  = G.map ((a #<=) . qOR) ksORs
  fzqs = G.map getQinFZ gms
  (grid, vtk) = mkSO3 35 35 35
  es = G.map (\s -> errorfunc (so3ToQuaternion s) ksORs fzqs) grid
  func i _ = es U.! i
  attr = mkPointAttr "Error function" func
  vtk' = addDataPoints vtk attr

  gi   = so3ToQuaternion $ grid U.! (U.minIndex es)
  in do
    let
      a'   = findGamma ksORs gms
      (a'', t'') = findGamma2 gms
      fa   = toFZ Cubic a
      fa'  = toFZ Cubic a'
      fa'' = toFZ Cubic a''
      fgi  = toFZ Cubic gi
      test g1 g2 = (fromAngle $ Deg 3) > (abs $ getOmega (g1 -#- g2))
    print "=================="
    print $ "Expect: " ++ show fa
    print (test fa fa')
    print $ testGammaFit a' gms ksOR
    print $ "from " ++ show fgi ++ " got: " ++ show fa'
    print (test fa fa'')
    print $ testGammaFit a'' gms t''
    print $ "from " ++ show fgi ++ " got: " ++ show fa''

    writeUniVTKfile ("/home/edgar/Desktop/SO3ErrFunc.vtu") False vtk'

    let vtk2 = renderSO3PointsVTK (U.map quaternionToSO3 $ U.fromList [gi, toFZ Cubic gi, a, a'])
    writeUniVTKfile ("/home/edgar/Desktop/SO3ErrFuncP.vtu") False vtk2

errorfuncSlowButSure :: Quaternion -> Vector Quaternion -> Quaternion -> Double
errorfuncSlowButSure ga gms t = abs $ 1 - (total / n)
  where
    os = V.map symmOp (getSymmOps Cubic)
    getMaxQ0 gm = let
      func on om = abs $ composeQ0 ((ga #<= on) -#- (gm #<= om)) t
      allQ0 = V.concatMap (\on -> V.map (func on) os) os
      in V.maximum allQ0

    total = G.sum $ G.map getMaxQ0 gms
    n     = fromIntegral (G.length gms)
