-- Copyright © 2015 Bart Massey

-- | Implementation of the "CipherSaber-2" RC4 encryption
-- format. Also provides a raw RC4 keystream generator.
--
-- This work is licensed under the "MIT License".  Please
-- see the file LICENSE in the source distribution of this
-- software for license terms.
module CipherSaber2 (rc4, encrypt, decrypt, toBytes, fromBytes) where

import Control.Monad
import Control.Monad.ST.Safe
import Data.Array.ST
import Data.Bits
import Data.Char
import Data.Word

-- | Number of bytes of IV to use in CipherSaber encryption/decryption
-- below. The standard CipherSaber IV size is 10 bytes.
ivLength :: Int
ivLength = 10

-- | Generate an RC4 keystream. CipherSaber recommends
-- a key of less than 54 bytes for best mixing. At most,
-- the first 256 bytes of the key are even used.
--
-- This function takes a parameter for the number of times
-- to repeat the key mixing loop ala "CipherSaber-2". It
-- should probably be set to at least 20.
-- 
-- This function takes a length of keystream to generate,
-- which is un-Haskellike but hard to avoid given the
-- strictness of 'STUArray'. An alternative would be to pass
-- the plaintext in and combine it here, but this interface
-- was chosen as "simpler". Another choice would be to leave
-- whole rc4 function in the 'ST' monad, but that seemed
-- obnoxious. The performance and usability implications of
-- these choices need to be explored.
rc4 :: Int -> Int -> [Word8] -> [Word8]
rc4 scheduleReps keystreamLength key =
    runST $ do
      -- Create and initialize the state.
      s <- newListArray (0, 255) [0..255] :: ST s (STUArray s Word8 Word8)
      -- One step of the key schedule
      let schedStep j i = do
            si <- readArray s i
            let keyByte = key !! (fromIntegral i `mod` length key)
            let j' = j + si + keyByte
            sj <- readArray s j'
            writeArray s i sj
            writeArray s j' si
            return j'
      -- Do the key scheduling.
      foldM_ schedStep 0 $ concat $ replicate scheduleReps [0..255]
      -- Do the keystream generation.
      let keystream 0 _ _ = return []
          keystream n i j = do
            let i' = i + 1
            si <- readArray s i'
            let j' = j + si
            sj <- readArray s j'
            writeArray s i' sj
            writeArray s j' si
            sk <- readArray s (si + sj)
            ks <- keystream (n - 1) i' j'
            return $ sk : ks
      -- Get the keystream.
      keystream keystreamLength 0 0

-- | Convert a 'String' to a list of bytes.
toBytes :: String -> [Word8]
toBytes s = map (fromIntegral . ord) s

-- | Convert a list of bytes to a 'String'.
fromBytes :: [Word8] -> String
fromBytes bs = map (chr . fromIntegral) bs

-- | CipherSaber requires using a 10-byte initial value (IV)
-- to protect against keystream recovery. Given the key and
-- IV, this code will turn a a sequence of plaintext message
-- bytes into a sequence of ciphertext bytes.
encrypt :: Int -> [Word8] -> [Word8] -> [Word8] -> [Word8]
encrypt scheduleReps key iv plaintext
    | length iv == ivLength =
        let keystream = rc4 scheduleReps (length plaintext) (key ++ iv) in
        iv ++ zipWith xor keystream plaintext
    | otherwise = error $ "expected IV length " ++ show ivLength

-- | CipherSaber recovers the 10-byte IV from the start of the
-- ciphertext.  Given the key, this code will turn a
-- sequence of ciphertext bytes into a sequence of plaintext
-- bytes.
decrypt :: Int -> [Word8] -> [Word8] -> [Word8]
decrypt scheduleReps key ciphertext0 =
    let (iv, ciphertext) = splitAt ivLength ciphertext0
        keystream = rc4 scheduleReps (length ciphertext) (key ++ iv) in
    zipWith xor keystream ciphertext
