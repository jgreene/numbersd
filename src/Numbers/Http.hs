-- |
-- Module      : Numbers.Http
-- Copyright   : (c) 2012 Brendan Hay <brendan@soundcloud.com>
-- License     : This Source Code Form is subject to the terms of
--               the Mozilla Public License, v. 2.0.
--               A copy of the MPL can be found in the LICENSE file or
--               you can obtain it at http://mozilla.org/MPL/2.0/.
-- Maintainer  : Brendan Hay <brendan@soundcloud.com>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--

module Numbers.Http (
      sinkHttp
    ) where

import Blaze.ByteString.Builder hiding (flush)
import Control.Monad
import Control.Monad.IO.Class
import Control.Concurrent.Async
import Data.Aeson               hiding (json)
import Data.Maybe
import Data.Text.Encoding              (decodeUtf8)
import Network.Wai
import Network.Wai.Parse
import Network.Wai.Handler.Warp
import Network.HTTP.Types
import Numbers.Log
import Numbers.Types
import Numbers.Conduit

import qualified Data.ByteString.Char8 as BS
import qualified Numbers.Whisper       as W

data ContentType = Json | Html | Text

sinkHttp :: Int -> Int -> Maybe Int -> Maybe (IO EventSink)
sinkHttp res step = fmap $ \port -> do
    w <- W.newWhisper res step

    async (run port $ liftIO . serve w) >>= link

    infoL $ "Serving /overview and /numbersd/<key> on http://0.0.0.0:" <&& port

    runSink . awaitForever $ \e -> case e of
        Flush ts p -> liftIO $ W.insert ts p w
        _          -> return ()

serve :: W.Whisper -> Request -> IO Response
serve whis req
    | isNothing a = return unacceptable
    | otherwise   = case pathInfo req of
        ["numbersd"]      -> series b whis
        ["numbersd", key] -> series b whis
        ["overview"]      -> return $ overview b []
        _                 -> return $ unknown b
  where
    a = getType req
    b = fromJust a

series :: ContentType -> W.Whisper -> IO Response
series typ whis = do
    ts <- currentTime
    response typ status200 `liftM` f ts ts whis
  where
    f = case typ of
        Json -> W.json
        _    -> W.text

getType :: Request -> Maybe ContentType
getType req = hAccept `lookup` requestHeaders req >>= f . parseHttpAccept
  where
    f h | p Json h  = return Json
        | p Html h  = return Text
        | p Text h  = return Text
        | otherwise = fail "Not Acceptable"
    p t = (pack t `elem`)

unacceptable :: Response
unacceptable = response Text status406 $ copyByteString "Not Acceptable"

unknown :: ContentType -> Response
unknown typ = response typ status404 $ copyByteString msg
  where
    msg = case typ of
        Json -> "{\"error\": \"Not Found\"}"
        _    -> "Not Found"

overview :: ContentType -> [(Key, Int)] -> Response
overview typ = response typ status200 . body
  where
    body = copyLazyByteString . encode . object . map f
    f (Key k, v) = decodeUtf8 k .= v

response :: ContentType -> Status -> Builder -> Response
response typ status = ResponseBuilder status [("Content-Type", pack typ)]

pack :: ContentType -> BS.ByteString
pack Json = "application/json"
pack Html = "text/html"
pack Text = "text/plain"