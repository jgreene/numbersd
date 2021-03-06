{-# LANGUAGE NoOverloadedStrings #-}

-- |
-- Module      : Main
-- Copyright   : (c) 2012 Brendan Hay <brendan@soundcloud.com>
-- License     : This Source Code Form is subject to the terms of
--               the Mozilla Public License, v. 2.0.
--               A copy of the MPL can be found in the LICENSE file or
--               you can obtain it at http://mozilla.org/MPL/2.0/.
-- Maintainer  : Brendan Hay <brendan@soundcloud.com>
-- Stability   : experimental
-- Portability : non-portable (GHC extensions)
--

module Main where

import Control.Concurrent.Async
import Control.Concurrent.STM
import Control.Monad
import Data.Maybe               (catMaybes)
import Numbers.Conduit
import Numbers.Config
import Numbers.Http
import Numbers.Log
import Numbers.Store

main :: IO ()
main = withSocketsDo $ do
    conf@Config{..} <- parseConfig

    buf <- atomically $ newTBQueue _buffer
    infoL "Buffering..."

    ls  <- mapM (asyncLink . (`sourceUri` buf)) _listeners
    infoL "Listeners started..."

    ss  <- sequence $
        catMaybes [sinkHttp conf, sinkLog _logEvents]
        ++ map (newSink (graphite _prefix)) _graphites
        ++ map (newSink broadcast) _broadcasts
        ++ map (newSink downstream) _downstreams
    infoL "Sinks started..."

    sto <- asyncLink $ runStore _percentiles _interval ss buf
    infoL "Store started..."

    void . waitAnyCancel $ sto:ls

asyncLink :: IO a -> IO (Async a)
asyncLink io = do
    a <- async io
    link a
    return a