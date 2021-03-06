
module Laborantin where

import Laborantin.Types
import Laborantin.DSL
import Laborantin.Implementation
import Control.Monad.IO.Class
import Control.Monad.Reader
import Control.Monad.Error
import Control.Applicative
import qualified Data.Set as S

execute :: (MonadIO m) => Backend m -> ScenarioDescription m -> ParameterSet -> m ()
execute b sc prm = execution
  where execution = do
            (exec,final) <- bPrepareExecution b sc prm 
            status <- runReaderT (runErrorT (go exec `catchError` recover exec)) (b, exec)
            let exec' = either (\_ -> exec {eStatus = Failure}) (\_ -> exec {eStatus = Success}) status
            bFinalizeExecution b exec' final
            where go exec = do 
                        bSetup b exec
                        bRun b exec
                        bTeardown b exec
                        bAnalyze b exec
                  recover exec err = bRecover b err exec >> throwError err

executeAnalysis :: (MonadIO m, Functor m) => Backend m -> Execution m -> m (Either AnalysisError ())
executeAnalysis b exec = do
    either rebrandError Right <$> runReaderT (runErrorT (go exec)) (b, exec)
    where go exec = bAnalyze b exec
          rebrandError (ExecutionError str) = Left $ AnalysisError str


executeExhaustive :: (MonadIO m) => Backend m -> ScenarioDescription m -> [m ()]
executeExhaustive b sc = map f $ paramSets $ sParams sc
    where f = execute b sc 

executeMissing :: (MonadIO m) => Backend m -> ScenarioDescription m -> [Execution m] -> [m ()]
executeMissing b sc execs = map f $ S.toList (exhaustive `S.difference` existing)
    where successful = filter ((== Success) . eStatus) execs
          exhaustive = S.fromList $ paramSets (sParams sc)
          existing = S.fromList $ map eParamSet successful
          f = execute b sc

load :: (MonadIO m) => Backend m -> [ScenarioDescription m] -> TExpr Bool -> m [Execution m]
load = bLoad

remove :: (MonadIO m) => Backend m -> Execution m -> m ()
remove = bRemove
