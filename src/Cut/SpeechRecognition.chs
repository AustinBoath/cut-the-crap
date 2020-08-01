{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeOperators    #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE DeriveAnyClass #-}

-- | This entire module leaks like crazy, it's not a big deal because
--   at the moment this process is confined
module Cut.SpeechRecognition(speechAnalyses
                            , frame_from
                            , frame_to
                            , frame_word
                            , FrameOffset
                            , WordFrame
                            , ResultCode(..)
                            , toDiffTime
                            , toFrameOffset
                            , noOffset 
                            ) where

import Data.Time
import           GHC.Generics
import Data.Text(Text)
import qualified Data.Text as Text
import Control.Monad (liftM, when)
import Foreign
import Foreign.C
import System.IO.Unsafe (unsafePerformIO)
import Control.Lens
import           Data.Generics.Product.Fields

#include "speech_recognition.h"

{#enum result_code as ResultCode {underscoreToCase}#}
deriving instance Show ResultCode

newtype FrameOffset = FrameOffset Int
  deriving (Generic, Show)

noOffset :: FrameOffset
noOffset = FrameOffset 0


toFrameOffset :: Int -> FrameOffset
toFrameOffset = FrameOffset

data WordFrame = WordFrame
  { _frame_from :: FrameOffset 
  , _frame_to :: FrameOffset 
  , _frame_word :: Text
  } deriving (Generic, Show)

instance Storable WordFrame where
        alignment _ = 4
        sizeOf _    = 16
        peek ptr    =
            WordFrame
              <$> (FrameOffset . toInt <$> peekByteOff ptr 0)
              <*> (FrameOffset . toInt <$> peekByteOff ptr 4)
              <*> (peekByteOff ptr 8 >>= fmap Text.pack . peekCString)
        poke ptr (WordFrame (FrameOffset d) (FrameOffset c) i) = do
            pokeByteOff ptr 0 d
            pokeByteOff ptr 4 c
            withCString (Text.unpack i) $ pokeByteOff ptr 8

frame_from :: Lens' WordFrame FrameOffset 
frame_from = field @"_frame_from"

frame_to :: Lens' WordFrame FrameOffset 
frame_to = field @"_frame_to"

toDiffTime :: FrameOffset -> FrameOffset -> DiffTime
toDiffTime (FrameOffset startoffset) (FrameOffset x) =
  secondsToDiffTime $ toInteger $ div (x - startoffset) 45

frame_word :: Lens' WordFrame Text
frame_word = field @"_frame_word"

toInt :: CInt -> Int
toInt = fromInteger . toInteger

detectedToList :: CInt -> Ptr WordFrame -> IO [WordFrame]
detectedToList c_used frames  =
  traverse (peek . plusPtr frames . (*) (sizeOf (undefined :: WordFrame)) ) [0..(used - 1)]
  where
    used = toInt c_used
    
-- | given a raw audio file, we can detect words
speechAnalyses :: FilePath -> IO (Either ResultCode [WordFrame])
speechAnalyses filePath = do
  c_result <- withCString filePath detect_words_ffi
  c_words <- peekByteOff c_result 8 
  c_words_used <- peekByteOff c_result 16 
  status_code <- toEnum . fromIntegral <$> {#get detect_result.code #} c_result
  case status_code of
    Success -> Right <$> detectedToList c_words_used c_words
    x -> pure $ Left x
    
foreign import ccall "detect_words" detect_words_ffi :: CString -> IO ({#type detect_result #}) 
