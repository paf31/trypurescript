module Try.API
  ( ErrorPosition(..)
  , CompilerError(..)
  , CompileError(..)
  , CompileWarning(..)
  , Suggestion(..)
  , SuccessResult(..)
  , FailedResult(..)
  , CompileResult(..)
  , Backend(..)
  , BackendConfig(..)
  , getBackendConfig
  , getBackendConfigFromString
  ) where

import Prelude

import Control.Alt ((<|>))
import Control.Monad.Cont.Trans (ContT(ContT))
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Uncurried (EffFn1, EffFn3, EffFn4, mkEffFn1, runEffFn3, runEffFn4)
import Control.Monad.Except (runExcept)
import Control.Monad.Except.Trans (ExceptT(ExceptT))
import Control.Parallel (parTraverse)
import DOM (DOM)
import Data.Array (fold, intercalate)
import Data.Either (Either(..))
import Data.Foreign (Foreign, ForeignError)
import Data.Foreign.Class (class Decode, decode)
import Data.Foreign.Generic (defaultOptions, genericDecode)
import Data.Foreign.Generic.Types (Options, SumEncoding(..))
import Data.Foreign.NullOrUndefined (NullOrUndefined)
import Data.Generic.Rep (class Generic)
import Data.List.NonEmpty (NonEmptyList)
import Data.String.Regex (replace)
import Data.String.Regex.Flags (global)
import Data.String.Regex.Unsafe (unsafeRegex)
import Partial.Unsafe (unsafePartial)
import Try.Types (JS(JS))

decodingOptions :: Options
decodingOptions = defaultOptions { unwrapSingleConstructors = true }

-- | The range of text associated with an error
newtype ErrorPosition = ErrorPosition
  { startLine :: Int
  , endLine :: Int
  , startColumn :: Int
  , endColumn :: Int
  }

derive instance genericErrorPosition :: Generic ErrorPosition _

instance decodeErrorPosition :: Decode ErrorPosition where
  decode = genericDecode decodingOptions

newtype CompilerError = CompilerError
  { message :: String
  , position :: NullOrUndefined ErrorPosition
  }

derive instance genericCompilerError :: Generic CompilerError _

instance decodeCompilerError :: Decode CompilerError where
  decode = genericDecode decodingOptions

-- | An error reported from the compile API.
data CompileError
  = CompilerErrors (Array CompilerError)
  | OtherError String

derive instance genericCompileError :: Generic CompileError _

instance decodeCompileError :: Decode CompileError where
  decode = genericDecode
    (defaultOptions
      { sumEncoding =
          TaggedObject
            { tagFieldName: "tag"
            , contentsFieldName: "contents"
            , constructorTagTransform: id
            }
      })

newtype Suggestion = Suggestion
  { replacement :: String
  , replaceRange :: NullOrUndefined ErrorPosition
  }

derive instance genericSuggestion :: Generic Suggestion _

instance decodeSuggestion :: Decode Suggestion where
  decode = genericDecode decodingOptions

newtype CompileWarning = CompileWarning
  { errorCode :: String
  , message :: String
  , position :: NullOrUndefined ErrorPosition
  , suggestion :: NullOrUndefined Suggestion
  }

derive instance genericCompileWarning :: Generic CompileWarning _

instance decodeCompileWarning :: Decode CompileWarning where
  decode = genericDecode decodingOptions

newtype SuccessResult = SuccessResult
  { js :: String
  , warnings :: NullOrUndefined (Array CompileWarning)
  }

derive instance genericSuccessResult :: Generic SuccessResult _

instance decodeSuccessResult :: Decode SuccessResult where
  decode = genericDecode decodingOptions

newtype FailedResult = FailedResult
  { error :: CompileError }

derive instance genericFailedResult :: Generic FailedResult _

instance decodeFailedResult :: Decode FailedResult where
  decode = genericDecode decodingOptions

-- | The result of calling the compile API.
data CompileResult
  = CompileSuccess SuccessResult
  | CompileFailed FailedResult

-- | Parse the result from the compile API and verify it
instance decodeCompileResult :: Decode CompileResult where
  decode f =
    CompileSuccess <$> genericDecode decodingOptions f
    <|> CompileFailed <$> genericDecode decodingOptions f

foreign import get_
  :: forall eff
   . EffFn3 (dom :: DOM | eff)
            String
            (EffFn1 (dom :: DOM | eff) String Unit)
            (EffFn1 (dom :: DOM | eff) String Unit)
            Unit

-- | A wrapper for `get` which uses `ContT`.
get :: forall eff. String -> ExceptT String (ContT Unit (Eff (dom :: DOM | eff))) String
get uri = ExceptT (ContT \k -> runEffFn3 get_ uri (mkEffFn1 (k <<< Right)) (mkEffFn1 (k <<< Left)))

-- | Get the default bundle
getDefaultBundle
  :: forall eff
   . String
  -> ExceptT String (ContT Unit (Eff (dom :: DOM | eff))) JS
getDefaultBundle endpoint = JS <$> get (endpoint <> "/bundle")

-- | Get the JS bundle for the Thermite backend, which includes additional dependencies
getThermiteBundle
  :: forall eff
   . String
  -> ExceptT String (ContT Unit (Eff (dom :: DOM | eff))) JS
getThermiteBundle endpoint =
  let getAll = parTraverse get
        [ "js/console.js"
        , "js/react.min.js"
        , "js/react-dom.min.js"
        , endpoint <> "/bundle"
        ]

      onComplete :: Partial
                 => Array String
                 -> JS
      onComplete [consoleScript, react, react_dom, bundle] =
        let replaced = bundle
                         # replace (unsafeRegex """require\("react"\)""" global) "window.React"
                         # replace (unsafeRegex """require\("react-dom"\)""" global) "window.ReactDOM"
                         # replace (unsafeRegex """require\("react-dom\/server"\)""" global) "window.ReactDOM"
        in JS (intercalate "\n" [consoleScript, react, react_dom, replaced])
  in unsafePartial onComplete <$> getAll

-- | POST the specified code to the Try PureScript API, and wait for
-- | a response.
foreign import compile_
  :: forall eff
   . EffFn4 (dom :: DOM | eff)
            String
            String
            (EffFn1 (dom :: DOM | eff) Foreign Unit)
            (EffFn1 (dom :: DOM | eff) String Unit)
            Unit

-- | A wrapper for `compileApi` which uses `ContT`.
compile
  :: forall eff
   . String
  -> String
  -> ExceptT String (ContT Unit (Eff (dom :: DOM | eff)))
       (Either (NonEmptyList ForeignError) CompileResult)
compile endpoint code = ExceptT (ContT \k -> runEffFn4 compile_ endpoint code (mkEffFn1 (k <<< Right <<< runExcept <<< decode)) (mkEffFn1 (k <<< Left)))

newtype BackendConfig = BackendConfig
  { backend       :: String
  , mainGist      :: String
  , extra_styling :: String
  , extra_body    :: String
  , compile       :: forall eff
                   . String
                  -> ExceptT String (ContT Unit (Eff (dom :: DOM | eff)))
                       (Either (NonEmptyList ForeignError) CompileResult)
  , getBundle     :: forall eff. ExceptT String (ContT Unit (Eff (dom :: DOM | eff))) JS
  }

data Backend
  = Core
  | Thermite
  | Slides
  | Mathbox
  | Behaviors
  | Flare

backendFromString :: Partial => String -> Backend
backendFromString "core"      = Core
backendFromString "thermite"  = Thermite
backendFromString "slides"    = Slides
backendFromString "mathbox"   = Mathbox
backendFromString "behaviors" = Behaviors
backendFromString "flare"     = Flare

backendToString :: Backend -> String
backendToString Core      = "core"
backendToString Thermite  = "thermite"
backendToString Slides    = "slides"
backendToString Mathbox   = "mathbox"
backendToString Behaviors = "behaviors"
backendToString Flare     = "flare"

derive instance eqBackend :: Eq Backend
derive instance ordBackend :: Ord Backend

getBackendConfig :: Backend -> BackendConfig
getBackendConfig Core = BackendConfig
  { backend: "core"
  , mainGist: "b57a766d417e109785540d584266fc33"
  , extra_styling: ""
  , extra_body: ""
  , compile: compile "https://compile.purescript.org/try"
  , getBundle: getDefaultBundle "https://compile.purescript.org/try"
  }
getBackendConfig Thermite = BackendConfig
  { backend: "thermite"
  , mainGist: "85383bb058471109cfef379bbb6bc11c"
  , extra_styling: """<link rel="stylesheet" href="//maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css">"""
  , extra_body: """<div id="app"></div>"""
  , compile: compile "https://compile.purescript.org/thermite"
  , getBundle: getThermiteBundle "https://compile.purescript.org/thermite"
  }
getBackendConfig Slides = BackendConfig
  { backend: "slides"
  , mainGist: "c62b5778a6a5f2bcd32dd97b294c068a"
  , extra_styling: """<link rel="stylesheet" href="css/slides.css">"""
  , extra_body: """<div id="main"></div>"""
  , compile: compile "https://compile.purescript.org/slides"
  , getBundle: getDefaultBundle "https://compile.purescript.org/slides"
  }
getBackendConfig Mathbox = BackendConfig
  { backend: "mathbox"
  , mainGist: "81f8bb3261b9c819d677de2ea54a4d2e"
  , extra_styling: fold
      [ """<script src="js/mathbox-bundle.js"></script>"""
      , """<link rel="stylesheet" href="css/mathbox.css">"""
      ]
  , extra_body: ""
  , compile: compile "https://compile.purescript.org/purescript-mathbox"
  , getBundle: getDefaultBundle "https://compile.purescript.org/purescript-mathbox"
  }
getBackendConfig Behaviors = BackendConfig
  { backend: "behaviors"
  , mainGist: "ff1e87f0872d2d891e77d209d8f7706d"
  , extra_styling: ""
  , extra_body: """<canvas id="canvas" width="800" height="600"></canvas>"""
  , compile: compile "https://compile.purescript.org/behaviors"
  , getBundle: getDefaultBundle "https://compile.purescript.org/behaviors"
  }
getBackendConfig Flare = BackendConfig
  { backend: "flare"
  , mainGist: "4f54d6dd213caa54d736ead597e17fee"
  , extra_styling: """<link rel="stylesheet" href="css/flare.css">"""
  , extra_body: fold
      [ """<div id="controls"></div>"""
      , """<div id="output"></div>"""
      , """<div id="tests"></div>"""
      , """<canvas id="canvas" width="800" height="600"></canvas>"""
      ]
  , compile: compile "https://compile.purescript.org/flare"
  , getBundle: getDefaultBundle "https://compile.purescript.org/flare"
  }

getBackendConfigFromString :: String -> BackendConfig
getBackendConfigFromString s = getBackendConfig (unsafePartial backendFromString s)
