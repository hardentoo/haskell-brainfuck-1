module Test.Eval (tests) where

import Test.QuickCheck
import Control.Monad.State
import Data.Int (Int8)
import Data.Char (chr)

import HaskBF.Parser
import HaskBF.Tape
import HaskBF.Eval
import Test.Helper

tests = $(testGroupGenerator)

evaluate :: Program -> Either BFExError BFTape
evaluate p = evalState (eval simulatorMachine p) emptyState

evaluateSucc :: Program -> (BFTape -> Bool) -> Bool
evaluateSucc p pred = either (const False) pred $ evaluate p

evaluateError :: Program -> (BFTape -> Bool) -> Bool
evaluateError p pred = either (pred . errTape) (const False) $ evaluate p

prop_EmptyProgram :: Bool
prop_EmptyProgram =
  evaluateSucc [] $ \(Tape _ current _) -> current == 0

prop_IncrementsDecrements :: Positive Int8 -> Positive Int8 -> Bool
prop_IncrementsDecrements (Positive incs) (Positive decs) =
  evaluateSucc program $ \(Tape _ current _) -> current == incs - decs
  where program = replicate (fromIntegral incs) Inc ++
                  replicate (fromIntegral decs) Dec

prop_simpleProgram :: Bool
prop_simpleProgram =
  evaluateSucc program $ \(Tape prev current next) -> current == 1 && head next == 4
  where program = [Inc, Inc,             -- +2
                   IncP,Inc,Inc,Inc,Inc, -- right +4
                   DecP,Dec              -- left -1
                  ]

prop_tapeOverflow :: Bool
prop_tapeOverflow =
  evaluateError program predicate
  where program = [Inc, Inc,             -- +2
                   IncP,Inc,Inc,Inc,Inc, -- right +4
                   DecP,DecP             -- left overflow
                  ]
        predicate (Tape [] 2 (4:0:_)) = True
        predicate _ = False

prop_PutByte :: Bool
prop_PutByte =
  out == [0, 1, 2, 1]
  where program = [PutByte, Inc, PutByte, Inc, PutByte, Dec, PutByte]
        res = execState (eval simulatorMachine program) emptyState
        out = simStateOutput res

prop_GetByte :: Bool
prop_GetByte =
  out == [0, 42]
  where program = [PutByte, Inc, GetByte, PutByte]
        res = execState (eval simulatorMachine program) (SimState [42] [])
        out = simStateOutput res

prop_DecLoop :: Bool
prop_DecLoop =
  out == [42,41..1] ++ [-1]
  where loop = Loop [PutByte, Dec]  -- print and dec
        -- start with pointer -> 42
        -- loop printing and decrementing
        -- dec and print once more when out of the loop
        program = replicate 42 Inc ++ [loop] ++ [Dec, PutByte]
        res = execState (eval simulatorMachine program) emptyState
        out = simStateOutput res

prop_EvalString :: Bool
prop_EvalString =
  out == [2]
  where program = "++."
        res = execState (evalStr simulatorMachine program) emptyState
        out = simStateOutput res

-- taken from http://www.hevanet.com/cristofd/brainfuck/
squares :: String
squares = "++++[>+++++<-]>[<+++++>-]+<+[\n    >[>+>+<<-]++>>[<<+>>-]>>>[-]++>[-]+\n    >>>+[[-]++++++>>>]<<<[[<++++++++<++>>-]+<.<[>----<-]<]\n    <<[>>>>>[>>>[-]+++++++++<[>-<-]+++++++++>[-[<->-]+[<<<]]<[>+<-]>]<<-]<<-\n]\n"

outToString :: [Int8] -> String
outToString = map (chr . fromIntegral)

prop_Squares :: Bool
prop_Squares =
  outToString out == expected
  where program = squares
        res = execState (evalStr simulatorMachine program) emptyState
        out = simStateOutput res
        expected = concat [show (n*n) ++ "\n" | n <- [0..100]]

-- taken from http://rosettacode.org/wiki/Even_or_odd
isOddCode :: String
isOddCode = " ,[>,----------]\n++<\n[->-[>+>>]>\n[+[-<+>]>+>>]\n<<<<<]\n>[-]<++++++++\n[>++++++<-]\n>[>+<-]>.\n"

digits :: Integer -> [Int8]
digits = reverse . digitsRev
  where digitsRev i = case i of
          0 -> []
          _ -> fromIntegral lastDigit : digitsRev rest
          where (rest, lastDigit) = quotRem i 10

prop_WithInput :: Positive Integer -> Bool
prop_WithInput (Positive n) =
  outToString out == expected
  where program = isOddCode
        res = execState (evalStr simulatorMachine program)
                        (SimState numDigits [])
        out = simStateOutput res
        numDigits = digits n ++ [fromIntegral (fromEnum '\n')]
        -- The program returns the string 1 for odd numbers and 0 for even
        expected = if odd n then "1" else "0"
