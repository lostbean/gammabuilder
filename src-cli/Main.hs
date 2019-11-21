{-# LANGUAGE RecordWildCards           #-}
{-# LANGUAGE ExistentialQuantification #-}

module Main where

import qualified Gamma.OR                   as OR
import qualified Gamma.Strategy.Graph       as Graph
import qualified Gamma.Strategy.ORFitAll    as ORFitAll
import qualified Gamma.Strategy.GomesGraph  as GomesGraph

import           System.Directory            (doesFileExist)
import           Control.Monad               (when)
import           Data.Word                   (Word8)

import           Options.Applicative
import           System.FilePath

import           Texture.Orientation         (Deg(..), mkAxisPair, AxisPair)
import           Linear.Vect

-- ===================================== Data & class ====================================

class ParserCmdLine a where
  runAlgo  :: a -> IO ()
  validate :: a -> IO (Either a String)

data RunMode = forall a . ParserCmdLine a => RunMode {config :: a}

-- ========================================= Main ========================================

parseMode :: Parser RunMode
parseMode = subparser
 ( command "micro-features"
   (info (RunMode <$> parseShowGraph)
   (progDesc "Identify grain's ID, vertexes, edges and faces."))
 <> command "optimum-OR"
   (info (RunMode <$> parseORFitAll)
   (progDesc "Finds the best Orientation Relationship."))
 <> command "reconstruction"
   (info (RunMode <$> parseGomesGraph)
   (progDesc "Reconstruction based on Gomes's method (graph clustering)."))
 )

main :: IO ()
main = do
  RunMode mode <- execParser opts
  cfg <- validate mode
  case cfg of
    Left  c -> runAlgo c
    Right s -> error s
  where
    opts = info (helper <*> parseMode)
           ( fullDesc
           <> progDesc "Reconstructs gamma phase from EBSD data"
           <> header "Gamma Builder" )

-- ======================================= Common tools ==================================

parseANGInputFile :: Parser String
parseANGInputFile = strOption
   (  long "input"
   <> short 'i'
   <> metavar "ANG_IN"
   <> help "Input file (.ang) target for correction." )

parseVTKOutputFile :: Parser (Maybe String)
parseVTKOutputFile = (optional . strOption)
   (  long "output"
   <> short 'o'
   <> metavar "VTK_OUT"
   <> help "VTK visualization.")

parseMisoAngle :: Parser Deg
parseMisoAngle = ((Deg . abs) <$> option auto
   (  long "grain-miso"
   <> short 'm'
   <> metavar "[Deg]"
   <> value 15
   <> help "The default error is 15 deg."))

parseOR :: Parser AxisPair
parseOR = let
  func :: (Int, Int, Int, Double) -> AxisPair
  func (v1, v2, v3, w) = mkAxisPair v (Deg w)
      where v = Vec3 (fromIntegral v1) (fromIntegral v2) (fromIntegral v3)
  in (func <$> option auto
   (  long "or"
   <> short 'r'
   <> metavar "\"(Int,Int,Int,Double)\""
   <> value (1,1,2,90)
   <> help "The default OR is KS <1,1,2> (Deg 90)."))

parseInOut :: Parser (FilePath, FilePath)
parseInOut = let
  func a b = (a, getStdOut a b)
  in func <$> parseANGInputFile <*> parseVTKOutputFile

getStdOut :: FilePath -> Maybe FilePath -> FilePath
getStdOut fin dout = let
 stdOutName = dropExtensions fin
 in case dout of
   Just x
     | isValid x -> dropExtensions x
     | otherwise -> stdOutName
   _ -> stdOutName

goodInputFile :: FilePath -> IO Bool
goodInputFile fin = do
  inOK <- doesFileExist fin
  when (not inOK) (putStrLn  $ "Invalid input file! " ++ fin)
  return inOK

testInputFile :: (a -> FilePath) -> a -> IO (Either a String)
testInputFile func cfg = do
    inOk <- goodInputFile (func cfg)
    return $ if inOk
      then Left cfg
      else Right "Failed to read the input file."

-- ========================================= ConnGraph ===================================

instance ParserCmdLine Graph.Cfg where
  runAlgo  = Graph.run
  validate = testInputFile Graph.ang_input

parseShowGraph :: Parser Graph.Cfg
parseShowGraph = let
  func m (fin, fout) = Graph.Cfg m fin fout
  in func
     <$> parseMisoAngle
     <*> parseInOut

-- ======================================= OR Fit All ====================================

instance ParserCmdLine ORFitAll.Cfg where
  runAlgo  = ORFitAll.run
  validate = testInputFile ORFitAll.ang_input

parseORFitAll :: Parser ORFitAll.Cfg
parseORFitAll = let
  func m (fin, fout) = ORFitAll.Cfg m fin fout
  in func
     <$> parseMisoAngle
     <*> parseInOut
     <*> parseORbyAvg
     <*> parseRenderORMap
     <*> parseORs

parseORs :: Parser [AxisPair]
parseORs = let
  func :: (Int, Int, Int, Double) -> AxisPair
  func (v1, v2, v3, w) = mkAxisPair v (Deg w)
      where v = Vec3 (fromIntegral v1) (fromIntegral v2) (fromIntegral v3)
  reader :: Parser (Int, Int, Int, Double)
  reader = argument auto
           (  metavar "(Int,Int,Int,Double)" <>
              help "The default OR is KS <1,1,2> (Deg 90).")
  in (map func <$> many reader)

parseORbyAvg :: Parser Bool
parseORbyAvg = switch
   (  long "or-by-avg"
   <> short 'a'
   <> help "Uses average grain orientation when optimizing OR")

parseRenderORMap :: Parser Bool
parseRenderORMap = switch
   (  long "vtk"
   <> short 'v'
   <> help "Renders grain boundaries map with OR misorientation values.")

-- ================================== GomesGraph =========================================

instance ParserCmdLine GomesGraph.Cfg where
  runAlgo  = GomesGraph.run
  validate = testInputFile GomesGraph.ang_input

parseGomesGraph :: Parser GomesGraph.Cfg
parseGomesGraph = let
  func m (fin, fout) mcl r f0 fk bw = GomesGraph.Cfg m fin fout mcl r f0 fk bw
  in func
     <$> parseMisoAngle
     <*> parseInOut
     <*> parseExtMCL
     <*> parseNoFloatingGrains
     <*> parseRefinementSteps
     <*> parseInitCluster
     <*> parseStepCluster
     <*> parseBadAngle
     <*> parseOR
     <*> optional parseParentPhaseID
     <*> parseOutputToANG
     <*> parseOutputToCTF

parseRefinementSteps :: Parser Word8
parseRefinementSteps = option auto
   (  long "refinement-steps"
   <> short 'n'
   <> metavar "Int"
   <> value 1
   <> help "Number of refinement steps. Default 1")

parseInitCluster :: Parser Double
parseInitCluster = (max 1.2 . abs) <$> option auto
   (  long "mcl-init-factor"
   <> short 's'
   <> metavar "Double"
   <> value 1.2
   <> help "Initial MCL factor. Default 1.2")

parseStepCluster :: Parser Double
parseStepCluster = let
  func :: Int -> Double
  func = (+ 1) . (/ 100) . fromIntegral . abs
  in func <$> option auto
   (  long "mcl-increase-factor"
   <> short 'x'
   <> metavar "Int[%]"
   <> value 5
   <> help "Increase ratio of MCL factor. Default 5%")

parseBadAngle :: Parser Deg
parseBadAngle = ((Deg . abs) <$> option auto
   (  long "bad-fit"
   <> short 'b'
   <> metavar "[Deg]"
   <> value 5
   <> help "The default error is 5 deg."))

parseParentPhaseID :: Parser OR.PhaseID
parseParentPhaseID = OR.PhaseID <$> option auto
   (  long "parentPhaseID"
   <> short 'g'
   <> metavar "Int"
   <> help "ID number of parent phase in the ANG file, if present.")

parseExtMCL :: Parser Bool
parseExtMCL = switch
   (  long "extMCL"
   <> help "Uses external software for clustering. Requires MCL installed")

parseNoFloatingGrains :: Parser Bool
parseNoFloatingGrains = switch
   (  long "excludeFloatingGrains"
   <> help "Exclude floating grains (grains without junctions) from the reconstruction.")

parseOutputToANG :: Parser Bool
parseOutputToANG = switch
   (  long "ang"
   <> help "Generate output OIM in ANG format.")

parseOutputToCTF :: Parser Bool
parseOutputToCTF = switch
   (  long "ctf"
   <> help "Generate output OIM in CTF format.")