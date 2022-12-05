module plis.parse;

import std.algorithm;
import std.range;
import std.ascii;
import std.conv;

import plis.debugger;

string sequenceName(int n, string prefix = "A") {
    return prefix ~ n.to!string.padLeft('0', 6).to!string;
}

string alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz";

string encodeSequenceNumber(int n) {
    assert(n >= 0, "Cannot encode negative integers");
    if(n == 0) {
        return alphabet[0..1];
    }
    string res;
    while(n > 0) {
        res ~= alphabet[n % alphabet.length];
        n /= alphabet.length;
    }
    return res;
}

int decodeSequenceNumber(string s) {
    int sum = 0;
    int base = 1;
    foreach(ch; s) {
        int index = alphabet.countUntil(ch);
        assert(index >= 0, "Invalid decode sequence entry: " ~ ch);
        sum += base * index;
        base *= alphabet.length;
    }
    return sum;
}

bool isANumber(string name) {
    return name.length >= 2 && isDigit(name[1]);
}

string normalizeSequenceName(string name) {
    if(isANumber(name)) {
        string digits;
        for(uint i = 1; i < name.length; i++) {
            assert(isDigit(name[i]),
                "Letter-digit names must have only digits after first letter");
            digits ~= name[i];
        }
        return sequenceName(digits.to!int);
    }
    else {
        return sequenceName(decodeSequenceNumber(name));
    }
}

// Cumulative Fold: [...]
// Map: {...}
enum TokenType {
    Unknown, Word, Operator, UnaryOperator,
    Comment, Reference, WordReference,
    Integer, String, Whitespace,
    Comma, Break,
    VariableSet,
    LeftParen, RightParen,
    LeftFold, RightFold,
    LeftMap, RightMap,
}

    
bool leftParen(TokenType type) {
    return type == TokenType.LeftParen
        || type == TokenType.LeftFold
        || type == TokenType.LeftMap;
}

struct Token {
    TokenType type;
    string raw;
    Token[] children;
    uint arity;
    
    string toString() {
        return "Token("
             ~ to!string(type) ~ ", " ~ raw ~ ", ["
             ~ children.map!(t => t.raw).join(" ").to!string ~ "])";
    }
    
    bool unary() {
        return type == TokenType.UnaryOperator
            || type == TokenType.RightFold
            || type == TokenType.RightMap;
    }
    
    bool leftParen() {
        return type.leftParen;
    }
    
    bool operator() {
        return unary
            || type == TokenType.Operator;
    }
}

// sorted by greedy precedence (i.e. longest first)
static string[] operators = [
    "<<", ">>",
    "*", "+", "-", "/", "%", "@", ":", "^", ".",
    // "|",
];
static int[string] precedence;
static bool[string] rightAssociative;
static this() {
    precedence = [
        "@":    13,
        "<<":   10,
        ">>":   10,
        ":":    10,
        ".":    10,
        "^":    8,
        "*":    7,
        "/":    7,
        "%":    7,
        "+":    4,
        "-":    4,
    ];
    rightAssociative = [
        "@":    false,
        "<<":   false,
        ">>":   false,
        ".":    false,
        "^":    true,    
        "*":    false,
        "/":    false,
        "+":    false,
        "-":    false,
        "%":    false,
        // "|":    false,
        ":":    true,
    ];
}

bool isWordInitial(T)(T c) { return isAlpha(c) || c == '_'; }
bool isWordBody(T)(T c) { return isAlphaNum(c) || c == '_'; }

// TODO: stream tokens
Token[] tokenize(string code) {
    Token[] build;
    TokenType lastSignificantType;
    bool[] parenIsDataStack = [];
    bool lastWasFunctor = false;
    bool lastRightParenWasFunctor = false;
    for(uint i = 0; i < code.length; i++) {
        Token cur;
        bool thisRightParenIsFunctor = false;
        if(isWordInitial(code[i])) {
            cur.type = TokenType.Word;
            while(i < code.length && isWordBody(code[i])) {
                cur.raw ~= code[i++];
            }
            i--;
        }
        else if(isDigit(code[i])) {
            cur.type = TokenType.Integer;
            while(i < code.length && isDigit(code[i])) {
                cur.raw ~= code[i++];
            }
            i--;
        }
        else if(code[i] == '$') {
            cur.raw ~= code[i++]; // add initial $
            assert(i < code.length, "Expected number after `$`");
            if(isDigit(code[i])) {
                cur.type = TokenType.Reference;
                while(i < code.length && isDigit(code[i])) {
                    cur.raw ~= code[i++];
                }
            }
            else {
                assert(isWordBody(code[i]), "Expected number or word after `$`");
                cur.type = TokenType.VariableSet;
                while(i < code.length && isWordBody(code[i])) {
                    cur.raw ~= code[i++];
                }
            }
            i--;
        }
        else if(code[i] == '&') {
            cur.type = TokenType.WordReference;
            cur.raw ~= code[i++]; // add initial &
            assert(i < code.length, "Expected word after `&`");
            assert(isWordInitial(code[i]), "Cannot start identifier with " ~ code[i]);
            while(i < code.length && isWordBody(code[i])) {
                cur.raw ~= code[i++];
            }
            i--;
        }
        else if(code[i] == '"') {
            cur.type = TokenType.String;
            cur.raw ~= code[i++]; // add initial "
            while(i < code.length && code[i] != '"') {
                cur.raw ~= code[i++];
            }
            cur.raw ~= code[i]; // add final "
            assert(cur.raw.length > 1 && cur.raw.back == '"', "Expected closing quote");
        }
        else if(isWhite(code[i])) {
            // TODO: collapse strings of consecutive whitespace
            cur.type = TokenType.Whitespace;
            cur.raw ~= code[i];
        }
        else if(code[i] == '(') {
            cur.type = TokenType.LeftParen;
            cur.raw ~= code[i];
            parenIsDataStack ~= lastWasFunctor;
        }
        else if(code[i] == ')') {
            cur.type = TokenType.RightParen;
            cur.raw ~= code[i];
            thisRightParenIsFunctor = parenIsDataStack.back;
            parenIsDataStack.popBack;
        }
        else if(code[i] == '[') {
            cur.type = TokenType.LeftFold;
            cur.raw ~= code[i];
        }
        else if(code[i] == ']') {
            cur.type = TokenType.RightFold;
            cur.raw ~= code[i];
        }
        else if(code[i] == '{') {
            cur.type = TokenType.LeftMap;
            cur.raw ~= code[i];
        }
        else if(code[i] == '}') {
            cur.type = TokenType.RightMap;
            cur.raw ~= code[i];
        }
        else if(code[i] == ',') {
            cur.type = TokenType.Comma;
            cur.raw ~= code[i];
        }
        else if(code[i] == ';') {
            cur.type = TokenType.Break;
            cur.raw ~= code[i];
        }
        else if(code[i] == '#') {
            cur.type = TokenType.Comment;
            while(i < code.length && code[i] != '\n') {
                cur.raw ~= code[i++];
            }
        }
        else {
            foreach(op; operators) {
                if(i + op.length > code.length) {
                    continue;
                }
                bool matched = true;
                foreach(j, ch; op) {
                    if(code[i + j] != ch) {
                        matched = false;
                        break;
                    }
                }
                if(matched) {
                    // determine if unary or binary
                    cur.type = TokenType.Operator;
                    if(lastSignificantType == TokenType.Unknown
                    || lastSignificantType.leftParen
                    || lastSignificantType == TokenType.Operator
                    || lastSignificantType == TokenType.Break
                    || lastSignificantType == TokenType.Comma
                    || lastSignificantType == TokenType.UnaryOperator
                    || lastRightParenWasFunctor) {
                        cur.type = TokenType.UnaryOperator;
                    }
                    cur.raw = op;
                    i += op.length - 1;
                    break;
                }
            }
        }
        assert(cur.type != TokenType.Unknown, "Unknown token: " ~ code[i]);
        if(cur.type != TokenType.Whitespace && cur.type != TokenType.Comment) {
            lastSignificantType = cur.type;
            lastWasFunctor = cur.type == TokenType.WordReference
                          || cur.type == TokenType.VariableSet;
            lastRightParenWasFunctor = thisRightParenIsFunctor;
        }
        build ~= cur;
    }
    return build;
}
