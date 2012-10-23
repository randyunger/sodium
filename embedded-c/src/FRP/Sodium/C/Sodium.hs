{-# LANGUAGE GADTs, GeneralizedNewtypeDeriving, TypeOperators, TypeFamilies,
        FlexibleContexts, FlexibleInstances, ScopedTypeVariables, OverloadedStrings #-}

module FRP.Sodium.C.Sodium where

import Control.Applicative
import Control.Monad.State.Strict
import Data.ByteString (ByteString)
import Data.Int
import Data.IntMap (IntMap)
import qualified Data.IntMap as IM
import Data.List
import Data.Map (Map)
import qualified Data.Map as M
import Data.Maybe
import Data.Word
import Language.C
import Language.C.Data.Ident
import Language.C.Data.Position
import Language.C.Parser

data Value = Value {
        vaDecls :: [CDecl],
        vaStmts :: [CStat],
        vaExpr  :: CExpr
    }

class RType a where
    ctype :: a -> CTypeSpec
    r :: Value -> a
    unr :: a -> Value

konstant :: forall a . (RNum a, Integral a) => a -> R a
konstant i = r $ Value {
        vaDecls = [],
        vaStmts = [],
        vaExpr  = castedNumeric (ctype (undefined :: R a)) i
    }

variable :: Ident -> Value
variable ident = Value [] [] (CVar ident undefNode)

formatValue :: Ident -> Value -> [CBlockItem]
formatValue var va =
    map CBlockDecl (vaDecls va) ++
    map CBlockStmt (vaStmts va) ++
    map CBlockStmt [CExpr (Just $ CAssign CAssignOp (CVar var undefNode) (vaExpr va) undefNode) undefNode]

class RType (R a) => RNum a where
    data R a :: *
    constant :: a -> R a
    plus :: R a -> R a -> R a
    ra `plus` rb = r $ Value {
            vaDecls = vaDecls a ++ vaDecls b,
            vaStmts = vaStmts a ++ vaStmts b,
            vaExpr  = CBinary CAddOp (vaExpr a) (vaExpr b) undefNode
        }
      where a = unr ra
            b = unr rb

castedNumeric :: Integral i => CTypeSpec -> i -> CExpr
castedNumeric typ i = CCast
                        (CDecl [CTypeSpec typ] [] undefNode)
                        (CConst (CIntConst (CInteger (fromIntegral i) DecRepr noFlags) undefNode))
                        undefNode

instance RNum Int64 where
    newtype R Int64 = RInt64 Value
    constant = konstant
instance RType (R Int64) where
    ctype _ = CTypeDef (Ident "int64_t" 0 undefNode) undefNode
    r = RInt64
    unr (RInt64 v) = v

instance RNum Int32 where
    newtype R Int32 = RInt32 Value
    constant = konstant
instance RType (R Int32) where
    ctype _ = CTypeDef (Ident "int32_t" 0 undefNode) undefNode
    r = RInt32
    unr (RInt32 v) = v

instance RNum Int16 where
    newtype R Int16 = RInt16 Value
    constant = konstant
instance RType (R Int16) where
    ctype _ = CTypeDef (Ident "int16_t" 0 undefNode) undefNode
    r = RInt16
    unr (RInt16 v) = v

instance RNum Int8 where
    newtype R Int8 = RInt8 Value
    constant = konstant
instance RType (R Int8) where
    ctype _ = CTypeDef (Ident "int8_t" 0 undefNode) undefNode
    r = RInt8
    unr (RInt8 v) = v

instance RNum Word64 where
    newtype R Word64 = RWord64 Value
    constant = konstant
instance RType (R Word64) where
    ctype _ = CTypeDef (Ident "uint64_t" 0 undefNode) undefNode
    r = RWord64
    unr (RWord64 v) = v

instance RNum Word32 where
    newtype R Word32 = RWord32 Value
    constant = konstant
instance RType (R Word32) where
    ctype _ = CTypeDef (Ident "uint32_t" 0 undefNode) undefNode
    r = RWord32
    unr (RWord32 v) = v

instance RNum Word16 where
    newtype R Word16 = RWord16 Value
    constant = konstant
instance RType (R Word16) where
    ctype _ = CTypeDef (Ident "uint16_t" 0 undefNode) undefNode
    r = RWord16
    unr (RWord16 v) = v

instance RNum Word8 where
    newtype R Word8 = RWord8 Value
    constant = konstant
instance RType (R Word8) where
    ctype _ = CTypeDef (Ident "uint8_t" 0 undefNode) undefNode
    r = RWord8
    unr (RWord8 v) = v

data Behavior a = Behavior Int
data Event a = Event Int

data EventImpl where
    To :: CTypeSpec -> Int -> EventImpl
    MapE :: CTypeSpec -> (Value -> Value) -> Int -> EventImpl
    Code :: CTypeSpec -> String -> CStat -> EventImpl
    
typeOf :: EventImpl -> CTypeSpec
typeOf (To t _) = t
typeOf (MapE t _ _) = t
typeOf (Code t _ _) = t

data ReactiveState = ReactiveState {
        rsInputType :: CTypeSpec,
        rsInputs    :: [Int],
        rsNextIdent :: String,
        rsNextEvent :: Int,
        rsEvents    :: IntMap [EventImpl]
    }

newReactiveState :: CTypeSpec -> ReactiveState
newReactiveState typ = ReactiveState {
        rsInputType = typ,
        rsInputs    = [],
        rsNextIdent = "__a",
        rsNextEvent = 2,
        rsEvents    = IM.empty
    }

toC :: ReactiveState -> [CExternalDeclaration NodeInfo]
toC rs = [
        CFDefExt $ CFunDef [
                CTypeSpec (CVoidType undefNode)
            ]
            (
                CDeclr (Just $ Ident "react" 0 undefNode) [
                        CFunDeclr (Right ([
                            mkVarDecl (rsInputType rs) (transferVarOf . rsInputType $ rs)
                        ], False)) [] undefNode
                    ] Nothing [] undefNode
            )
            []
            (
                CCompound [] (transferDecls ++ stmts) undefNode
            )
            undefNode
    ]
  where
    implsType :: [EventImpl] -> CTypeSpec
    implsType = fromMaybe (CVoidType undefNode) .
                fmap typeOf .
                listToMaybe
    inputTypeOf :: Int -> CTypeSpec
    inputTypeOf ix = implsType $ fromMaybe [] $ ix `IM.lookup` rsEvents rs
    transferVars :: Map String (CTypeSpec, Ident)
    transferVars = fst $ foldl' (\(m, nextIdent) evImpls ->
            let ty = implsType evImpls
                tyName = show ty
            in  case tyName `M.lookup` m of
                    Just _ -> (m, nextIdent)
                    Nothing ->
                        let ident = nextIdent
                        in  (M.insert tyName (ty, Ident ident 0 undefNode) m, succIdent nextIdent)
        ) (M.empty, rsNextIdent rs) (IM.elems (rsEvents rs)) 
    transferVarOf :: CTypeSpec -> Ident
    transferVarOf ty = snd $ fromMaybe (error $ "non-existent transfer variable type "++show ty) $
        show ty `M.lookup` transferVars
    mkVarDecl :: CTypeSpec -> Ident -> CDecl
    mkVarDecl ty ident = 
        let tyDecl = CTypeSpec ty
            declr = CDeclr (Just ident) [] Nothing [] undefNode
        in  CDecl [tyDecl] [(Just declr, Nothing, Nothing)] undefNode
    transferDecls :: [CBlockItem]
    transferDecls = map (\(ty, ident) ->  CBlockDecl $ mkVarDecl ty ident)
        (M.elems . M.delete (show (rsInputType rs)) $ transferVars) 
    mkLabel ix = Ident ("l"++show ix) 0 undefNode
    stmts = flip concatMap (IM.toList (rsEvents rs)) $ \(ix, impls) ->
        let stmts = 
                flip concatMap impls $ \impl ->
                    case impl of
                        To ty to -> [CGoto (mkLabel to) undefNode]
                        MapE ty f to ->
                            let ivar = transferVarOf ty
                                ovar = transferVarOf (inputTypeOf to)
                            in
                                [CCompound []
                                    (formatValue ovar (f (variable ivar)))
                                    undefNode,
                                    CGoto (mkLabel to) undefNode
                                ]
                        Code ty var stmt -> [
                            let ivar = transferVarOf ty
                            in  CCompound [] [
                                    CBlockDecl (
                                        let declr = CDeclr (Just (Ident var 0 undefNode)) [] Nothing [] undefNode
                                            ass = CInitExpr (CVar ivar undefNode) undefNode 
                                        in  CDecl [CTypeSpec ty] [(Just declr, Just ass, Nothing)] undefNode 
                                    ),
                                    CBlockStmt (fmap (const undefNode) stmt)
                                ] undefNode
                            ]
        in  case stmts of
                [] -> []
                (st:sts) -> CBlockStmt (CLabel (mkLabel ix) st [] undefNode) : map CBlockStmt sts

newtype Reactive a = Reactive { unReactive :: State ReactiveState a }
    deriving (Functor, Applicative, Monad)

connect :: Int -> EventImpl -> Reactive ()
connect i impl = Reactive $ modify $ \rs -> rs {
        rsEvents = IM.alter (Just . (impl:) . fromMaybe []) i (rsEvents rs)
    }

succIdent :: String -> String
succIdent = reverse . ii . reverse
  where
    ii [] = ['a']
    ii underscores@('_':_) = underscores
    ii ('z':xs) = 'a' : ii xs
    ii (x:xs)   = succ x : xs

never :: Event a
never = Event 0

allocEvent :: Reactive Int
allocEvent = Reactive $ do
    e <- gets rsNextEvent
    modify $ \rs -> rs { rsNextEvent = rsNextEvent rs + 1 }
    return e

merge :: forall a . RType a => Event a -> Event a -> Reactive (Event a)
merge (Event ea) (Event eb) = do
    ec <- allocEvent
    let ty = ctype (undefined :: a)
    connect ea (To ty ec)
    connect eb (To ty ec)
    return $ Event ec

mapE :: forall a b . (RType a, RType b) => (a -> b) -> Event a -> Reactive (Event b)
mapE f (Event ea) = do
    eb <- allocEvent
    let ty = ctype (undefined :: a)
    connect ea (MapE ty (\v -> unr (f (r v))) eb)
    return $ Event eb

listen :: forall a . RType a => Event a
       -> String     -- ^ Variable identifier
       -> ByteString -- ^ Statement or statement block to handle it
       -> Reactive ()
listen (Event ea) ident statement = do
    case execParser statementP statement (position 0 "blah" 1 1) [Ident "hello" 0 undefNode] (map Name [0..]) of
        Left err -> fail $ "parse failed in listen: " ++ show err
        Right (stmt, _) -> do
            let ty = ctype (undefined :: a)
            connect ea (Code ty ident stmt)

react :: forall a . RType a => (Event a -> Reactive ()) -> ReactiveState
react r = execState (unReactive (r (Event 1))) (newReactiveState (ctype (undefined :: a)))

main :: IO ()
main = do
    let st = react $ \ea -> do
            eb <- mapE (`plus` constant (1 :: Int32)) ea
            listen eb "x" "{ printf(\"x=%d\\n\", x); }"
            return ()
    putStrLn $ show $ pretty $ CTranslUnit (toC st) undefNode
