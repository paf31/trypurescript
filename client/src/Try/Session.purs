module Try.Session
  ( storeSession
  , tryRetrieveSession
  , createSessionIdIfNecessary
  ) where

import Prelude

import Data.Functor.App (App(..))
import Data.Int (hexadecimal, toStringAs)
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.Nullable (Nullable, toMaybe)
import Data.String as String
import Effect (Effect)
import Effect.Random (randomInt)
import Effect.Uncurried (EffectFn1, EffectFn2, runEffectFn1, runEffectFn2)
import Try.QueryString (getQueryStringMaybe, setQueryString)

randomGuid :: Effect String
randomGuid =
    unwrap (App s4 <> App s4 <> pure "-" <>
            App s4 <> pure "-" <>
            App s4 <> pure "-" <>
            App s4 <> pure "-" <>
            App s4 <> App s4 <> App s4)
  where
    s4 = padLeft <<< toStringAs hexadecimal <$> randomInt 0 (256 * 256)
    padLeft s = String.drop (String.length s - 1) ("000" <> s)

foreign import storeSession_ :: EffectFn2 String { code :: String } Unit

-- | Store the current session state in local storage
storeSession
  :: String
  -> { code :: String }
  -> Effect Unit
storeSession sessionId values = runEffectFn2 storeSession_ sessionId values

foreign import tryRetrieveSession_ :: EffectFn1 String (Nullable { code :: String })

-- | Retrieve the session state from local storage
tryRetrieveSession :: String -> Effect (Maybe { code :: String })
tryRetrieveSession sessionId = toMaybe <$> runEffectFn1 tryRetrieveSession_ sessionId

-- | Look up the session by ID, or create a new session ID.
createSessionIdIfNecessary :: Effect String
createSessionIdIfNecessary = do
  sessionId <- getQueryStringMaybe "session"
  case sessionId of
    Just sessionId_ -> pure sessionId_
    Nothing -> do
      id <- randomGuid
      setQueryString "session" id
      pure id
