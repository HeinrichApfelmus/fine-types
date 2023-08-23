-- | Parser for a FineTypes 'Module'.
module Language.FineTypes.Parser
    ( parseFineTypes
    ) where

import Prelude

import Data.Void
    ( Void
    )
import Language.FineTypes.Module
    ( Declarations
    , Module (Module)
    )
import Language.FineTypes.Typ
    ( ConstructorName
    , FieldName
    , OpOne (..)
    , OpTwo (..)
    , Typ (..)
    , TypConst (..)
    , TypName
    )
import Text.Megaparsec
    ( Parsec
    , between
    , endBy
    , many
    , parseMaybe
    , satisfy
    , sepBy
    , try
    , (<?>)
    , (<|>)
    )

import qualified Control.Monad.Combinators.Expr as Parser.Expr
import qualified Data.Map.Strict as Map
import qualified Text.Megaparsec.Char as Parser.Char
import qualified Text.Megaparsec.Char.Lexer as L

{-----------------------------------------------------------------------------
    Exported functions
------------------------------------------------------------------------------}

-- | Parse a 'String' containing mathematical types,
-- as they appears in the Cardano ledger specification.
parseFineTypes :: String -> Maybe Module
parseFineTypes = parseMaybe document

{-----------------------------------------------------------------------------
    Parser
------------------------------------------------------------------------------}
{- Note
For the design patterns used when implementing this parser, see
  J. Willis, N. Wu, Design Patterns for Parser Combinators (Functional Pearl)
  https://dl.acm.org/doi/10.1145/3471874.3472984
-}

type Parser = Parsec Void String

document :: Parser Module
document = space *> module'

module' :: Parser Module
module' =
    Module
        <$ symbol "module"
        <*> moduleName
        <* symbol "where"
        <*> declarations

declarations :: Parser Declarations
declarations = mconcat <$> (declaration `endBy` symbol ";")

-- | Parse a single declaration
declaration :: Parser Declarations
declaration =
    Map.singleton <$> lhs <* symbol "=" <*> rhs
  where
    lhs = typName
    rhs = try abstract <|> try productN <|> try sumN <|> expr

abstract :: Parser Typ
abstract = Abstract <$ symbol "_"

productN :: Parser Typ
productN = ProductN <$> braces (field `sepBy` symbol ",")

field :: Parser (FieldName, Typ)
field = (,) <$> fieldName <* symbol ":" <*> expr

sumN :: Parser Typ
sumN = SumN <$> sumBraces (constructor `sepBy` symbol ",")

constructor :: Parser (FieldName, Typ)
constructor = (,) <$> constructorName <* symbol ":" <*> expr

-- | Parse an expression.
expr :: Parser Typ
expr = Parser.Expr.makeExprParser atom tableOfOperators <?> "expression"

atom :: Parser Typ
atom =
    parens expr
        <|> (try (Zero <$> constants) <|> (Var <$> typName))
        <?> "atom"

constants :: Parser TypConst
constants =
    (Bool <$ symbol "Bool")
        <|> (Bytes <$ symbol "Bytes")
        <|> (Integer <$ symbol "ℤ")
        <|> (Natural <$ symbol "ℕ")
        <|> (Text <$ symbol "Text")
        <|> (Unit <$ symbol "Unit")

tableOfOperators :: [[Parser.Expr.Operator Parser Typ]]
tableOfOperators =
    [
        [ postfix "*" (One Sequence)
        , postfix "?" (One Option)
        ]
    ,
        [ prefix "ℙ" (One PowerSet)
        ]
    ,
        [ binaryR "×" (Two Product2)
        ]
    ,
        [ binaryR "⊎" (Two Sum2)
        , binaryR "+" (Two Sum2)
        ]
    ,
        [ binaryR "→∗" (Two FiniteSupport)
        , binaryR "↦0" (Two FiniteSupport)
        , binaryR "↦" (Two PartialFunction)
        ]
    ]

binaryR :: String -> (a -> a -> a) -> Parser.Expr.Operator Parser a
binaryR name f = Parser.Expr.InfixR (f <$ symbol name)

prefix
    , postfix
        :: String -> (a -> a) -> Parser.Expr.Operator Parser a
prefix name f = Parser.Expr.Prefix (f <$ symbol name)
postfix name f = Parser.Expr.Postfix (f <$ symbol name)

{-----------------------------------------------------------------------------
    Lexer
------------------------------------------------------------------------------}
lineComment :: Parser ()
lineComment = L.skipLineComment "--"

blockComment :: Parser ()
blockComment = L.skipBlockComment "{-" "-}"

space :: Parser ()
space = L.space Parser.Char.space1 lineComment blockComment

symbol :: String -> Parser String
symbol = L.symbol space

moduleName :: Parser String
moduleName = typName

typName :: Parser TypName
typName =
    L.lexeme space
        $ (:)
            <$> Parser.Char.upperChar
            <*> many (Parser.Char.alphaNumChar <|> satisfy (`elem` "_^"))

constructorName :: Parser ConstructorName
constructorName = fieldName

fieldName :: Parser FieldName
fieldName =
    L.lexeme space
        $ (:)
            <$> Parser.Char.lowerChar
            <*> many (Parser.Char.alphaNumChar <|> satisfy (`elem` "_^"))

parens :: Parser a -> Parser a
parens = between (symbol "(") (symbol ")")

braces :: Parser a -> Parser a
braces = between (symbol "{") (symbol "}")

sumBraces :: Parser a -> Parser a
sumBraces = between (symbol "Σ{") (symbol "}")