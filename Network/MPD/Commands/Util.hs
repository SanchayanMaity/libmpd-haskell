{-# LANGUAGE OverloadedStrings #-}
-- | Module    : Network.MPD.Commands.Util
-- Copyright   : (c) Ben Sinclair 2005-2009, Joachim Fasting 2010
-- License     : LGPL (see LICENSE)
-- Maintainer  : Joachim Fasting <joachim.fasting@gmail.com>
-- Stability   : alpha
--
-- Internal utilities for implementing MPD commands.

module Network.MPD.Commands.Util where

import           Network.MPD.Commands.Parse
import           Network.MPD.Commands.Types
import           Network.MPD.Core
import           Network.MPD.Util

import           Control.Monad.Error
import           Data.List (intersperse)
import           Data.Maybe (mapMaybe)

import           Data.ByteString.Char8 (ByteString)

-- Run getResponse but discard the response.
getResponse_ :: MonadMPD m => String -> m ()
getResponse_ x = getResponse x >> return ()

-- Get the lines of the daemon's response to a list of commands.
getResponses :: MonadMPD m => [String] -> m [ByteString]
getResponses cmds = getResponse . concat $ intersperse "\n" cmds'
    where cmds' = "command_list_begin" : cmds ++ ["command_list_end"]

-- Helper that throws unexpected error if input is empty.
failOnEmpty :: MonadMPD m => [ByteString] -> m [ByteString]
failOnEmpty [] = throwError $ Unexpected "Non-empty response expected."
failOnEmpty xs = return xs

-- A wrapper for getResponse that fails on non-empty responses.
getResponse1 :: MonadMPD m => String -> m [ByteString]
getResponse1 x = getResponse x >>= failOnEmpty

-- Run 'toAssocList' and return only the values.
takeValues :: [ByteString] -> [ByteString]
takeValues = snd . unzip . toAssocList

-- Separate the result of an lsinfo\/listallinfo call into directories,
-- playlists, and songs.
takeEntries :: MonadMPD m => [ByteString] -> m [LsResult]
takeEntries = mapM toEntry . splitGroups groupHeads . toAssocList
    where
        toEntry xs@(("file",_):_)   = LsSong `liftM` runParser parseSong xs
        toEntry (("directory",d):_) = (return . LsDirectory . Path) d
        toEntry (("playlist",pl):_) = (return . LsPlaylist . PlaylistName) pl
        toEntry _ = error "takeEntries: splitGroups is broken"
        groupHeads = ["file", "directory", "playlist"]

-- Extract a subset of songs, directories, and playlists.
extractEntries :: (Song -> Maybe a, PlaylistName -> Maybe a, Path -> Maybe a)
               -> [LsResult] -> [a]
extractEntries (fSong,fPlayList,fDir) = mapMaybe f
    where
        f (LsSong s) = fSong s
        f (LsPlaylist pl)  = fPlayList pl
        f (LsDirectory d)  = fDir d

-- Build a list of song instances from a response.
takeSongs :: MonadMPD m => [ByteString] -> m [Song]
takeSongs = mapM (runParser parseSong)
          . splitGroups ["file"]
          . toAssocList