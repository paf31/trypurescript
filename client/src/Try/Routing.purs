module Try.Routing where

import Prelude
import Data.Foldable (oneOf)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Routing.Match (Match, end, param, root)
import Try.Common (AuthCode(..), Compressed(..), GistID(..), gistQP, pursQP)

{-
Handles navigation within the single-page-app.
-}
--
data Route
  = AuthorizeCallback AuthCode Compressed
  | LoadCompressed Compressed
  | LoadGist GistID
  | Home

derive instance genericRoute :: Generic Route _

instance showRoute :: Show Route where
  show = genericShow

route :: Match Route
route =
  root
    *> oneOf
        [ AuthorizeCallback <$> (AuthCode <$> param "code") <*> (Compressed <$> param pursQP)
        , LoadCompressed <$> Compressed <$> param pursQP
        , LoadGist <$> GistID <$> param gistQP
        , Home <$ end
        ]
