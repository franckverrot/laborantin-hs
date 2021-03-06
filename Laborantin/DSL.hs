{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE FlexibleContexts #-}

module Laborantin.DSL (
        scenario
    ,   describe
    ,   parameter
    ,   dependency
    ,   check
    ,   resolve
    ,   values
    ,   str
    ,   num
    ,   range
    ,   arr
    ,   setup
    ,   teardown
    ,   run
    ,   param
    ,   getVar
    ,   setVar
    ,   recover
    ,   analyze
    ,   result
    ,   writeResult
    ,   appendResult
    ,   logger
    ,   dbg
    ,   err
) where

import qualified Data.Map as M
import Laborantin.Types
import Control.Monad.State
import Control.Monad.Reader
import Control.Monad.Error
import Control.Applicative
import Data.Dynamic
import Data.Text (Text, unpack)

class Describable a where
  changeDescription :: Text -> a -> a

instance Describable (ScenarioDescription a) where
  changeDescription d sc = sc { sDesc = d }

instance Describable ParameterDescription where
  changeDescription d pa = pa { pDesc = d }

instance Describable (Dependency a) where
  changeDescription d dep = dep { dDesc = d }

-- | DSL entry point to build a 'ScenarioDescription'.
scenario :: Text -> State (ScenarioDescription m) () -> ScenarioDescription m
scenario name f = execState f sc0
  where sc0 = SDesc name "" M.empty M.empty Nothing []

-- | Attach a description to the 'Parameter' / 'Scnario'
describe :: Describable a => Text -> State a ()
describe desc = modify (changeDescription desc)

-- | DSL entry point to build a 'ParameterDescription' within a scenario.
parameter :: Text -> State ParameterDescription () -> State (ScenarioDescription m) ()
parameter name f = modify (addParam name param)
  where addParam k v sc0 = sc0 { sParams = M.insert k v (sParams sc0) }
        param = execState f param0
                where param0 = PDesc name "" []

-- | DSL entry point to build a 'Dependency a' within a scenario.
dependency :: (Monad m) => Text -> State (Dependency m) () -> State (ScenarioDescription m) ()
dependency name f = modify (addDep dep)
  where addDep v sc0 = sc0 { sDeps = v:(sDeps sc0)}
        dep = execState f dep0
              where dep0 = Dep name "" (const (return True)) (const (return ()))

-- | Set verification action for the dependency
check :: (Execution m -> m Bool) -> State (Dependency m) ()
check f = do
  dep0 <- get
  put $ dep0 { dCheck = f }

-- | Set resolution action for the dependency
resolve :: (Execution m -> m ()) -> State (Dependency m) ()
resolve f = do
  dep0 <- get
  put $ dep0 { dSolve = f }

-- | Set default values for the paramater
values :: [ParameterValue] -> State ParameterDescription ()
values xs = do
  param0 <- get
  put $ param0 { pValues = xs }

-- | Encapsulate a Text as a 'ParameterValue'
str :: Text -> ParameterValue
str = StringParam

-- | Encapsulate an integer value as a 'ParameterValue'
num :: Integer -> ParameterValue
num = NumberParam . fromInteger

-- | Encapsulate a range as a 'ParameterValue'
range :: Rational -> Rational -> Rational -> ParameterValue
range = Range

-- | Encapsulate an array of 'str' or 'num' values as a 'ParameterValue'
arr :: [ParameterValue] -> ParameterValue
arr = Array

-- | Define the setup hook for this scenario
setup :: Step m () -> State (ScenarioDescription m) ()
setup = appendHook "setup"

-- | Define the main run hook for this scenario
run :: Step m () -> State (ScenarioDescription m) ()
run = appendHook "run"

-- | Define the teardown hook for this scenario
teardown :: Step m () -> State (ScenarioDescription m) ()
teardown  = appendHook "teardown"

-- | Define the recovery hook for this scenario
recover :: (ExecutionError -> Step m ()) -> State (ScenarioDescription m) ()
recover f = modify (setRecoveryAction action)
  where action err = Action (f err)
        setRecoveryAction act sc = sc { sRecoveryAction = Just act }

-- | Define the offline analysis hook for this scenario
analyze :: Step m () -> State (ScenarioDescription m) ()
analyze = appendHook "analyze"

appendHook :: Text -> Step m () -> State (ScenarioDescription m) ()
appendHook name f = modify (addHook name $ Action f)
  where addHook k v sc0 = sc0 { sHooks = M.insert k v (sHooks sc0) }

-- | Returns a 'Result' object for the given name.
--
-- Implementations will return their specific results.
result :: Monad m => FilePath -> Step m (Result m)
result name = do 
  (b,r) <- ask
  bResult b r name

-- | Write (overwrite) the result in its entirety.
--
-- Implementations will return their specific results.
writeResult :: Monad m => FilePath  -- ^ result name
                       -> Text  -- ^ result content
                       -> Step m ()
writeResult name dat = result name >>= flip pWrite dat

-- | Appends a chunk of data to the result. 
--
-- Implementations will return their specific results.
appendResult :: Monad m => FilePath -- ^ result name
                        -> Text -- ^ content to add
                        -> Step m ()
appendResult name dat = result name >>= flip pAppend dat

-- | Return a 'LogHandler' object for this scenario.
logger :: Monad m => Step m (LogHandler m)
logger = ask >>= uncurry bLogger

-- | Sends a line of data to the logger (debug mode)
dbg :: Monad m => Text -> Step m ()
dbg msg = logger >>= flip lLog msg

-- | Interrupts the scenario by throwing an error
err :: Monad m => String -> Step m ()
err = throwError . ExecutionError

-- | Get the parameter with given name.
-- Throw an error if the parameter is missing.
param :: Monad m => Text -- ^ the parameter name
                 -> Step m ParameterValue
param key = do
    ret <- liftM (M.lookup key . eParamSet . snd) ask
    maybe (throwError $ ExecutionError $ "missing param: " ++ unpack key) return ret

getVar' :: (Functor m, MonadState DynEnv m) => Text -> m (Maybe Dynamic)
getVar' k = M.lookup k <$> get

setVar' :: (MonadState DynEnv m) => Text -> Dynamic -> m ()
setVar' k v = modify (M.insert k v)

-- | Set an execution variable.
setVar :: (Typeable v, MonadState DynEnv m) =>
            Text -- ^ name of the variable
         -> v      -- ^ value of the variable
         -> m ()
setVar k v = setVar' k (toDyn v)

-- | Get an execution variable and tries to cast it from it's Dynamic
-- representation.
--
-- Returns 'Nothing' if the variable is missing or if it could not
-- be cast to the wanted type.
getVar :: (Typeable v, Functor m, MonadState DynEnv m) => 
            Text              -- ^ name of the variable
         -> m (Maybe v)      
getVar k = maybe Nothing fromDynamic <$> getVar' k

