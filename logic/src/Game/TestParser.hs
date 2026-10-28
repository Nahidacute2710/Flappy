
module Main where

import CommandParser (parseSimulationCommand)

main :: IO ()
main = do
    putStrLn "===== KIEM THU COMMAND PARSER ====="

    let testCases =
            [ ( "1. Lenh hop le - parallel"
              , "simulate frames=600 runs=10 mode=parallel"
              )
            , ( "2. Lenh hop le - sequential"
              , "simulate frames=60 runs=2 mode=sequential"
              )
            , ( "3. frames bang 0"
              , "simulate frames=0 runs=10 mode=parallel"
              )
            , ( "4. frames khong phai so"
              , "simulate frames=abc runs=10 mode=parallel"
              )
            , ( "5. Thieu mode"
              , "simulate frames=600 runs=10"
              )
            , ( "6. Vuot gioi han frames"
              , "simulate frames=200000 runs=10 mode=parallel"
              )
            , ( "7. Sai lenh"
              , "hello world"
              )
            ]

    mapM_ runTest testCases

runTest :: (String, String) -> IO ()
runTest (testName, command) = do
    putStrLn ("\n--- " ++ testName ++ " ---")
    putStrLn ("Input: " ++ command)

    case parseSimulationCommand command of
        Right config -> do
            putStrLn "Ket qua: THANH CONG"
            print config

        Left err -> do
            putStrLn "Ket qua: THAT BAI"
            putStrLn err
