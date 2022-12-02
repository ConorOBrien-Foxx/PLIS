module plis.interpret;

import plis.impl;

import std.algorithm;
import std.ascii;
import std.bigint;
import std.conv;
import std.range;
import std.sumtype;

alias FunctionTable = SequenceFunction[string];
FunctionTable generateFunctionTable() {
    FunctionTable fns;
    foreach(m; __traits(allMembers, plis.impl)) {
        static if(m[0] == 'A') {
            fns[m] = (BigInt a) => mixin(m ~ "(a)");
        }
    }
    return fns;
}

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

string normalizeSequenceName(string name) {
    if(name.length >= 2 && isDigit(name[1])) {
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
    Comment, Reference,
    //Fold, Map,
    Integer, Whitespace,
    LeftParen, RightParen,
    LeftFold, RightFold,
}
struct Token {
    TokenType type;
    string raw;
    Token[] children;
    
    string toString() {
        return "Token(" ~ to!string(type) ~ ", " ~ raw ~ ", " ~ children.to!string ~ ")";
    }
    
    bool unary() {
        return type == TokenType.UnaryOperator || type == TokenType.RightFold;
    }
    
    bool leftParen() {
        return type == TokenType.LeftParen || type == TokenType.LeftFold;
    }
}

// sorted by greedy precedence (i.e. longest first)
static string[] operators = [
    "<<", ">>",
    "*", "+", "-", "/", "@", ":", "^",
    // "|",
];
static int[string] precedence;
static bool[string] rightAssociative;
FunctionTable ftable;
static this() {
    precedence = [
        "@":    13,
        "<<":   10,
        ">>":   10,
        ":":    10,
        // "|":    10,
        "^":    8,
        "*":    7,
        "/":    7,
        "+":    4,
        "-":    4,
    ];
    rightAssociative = [
        "@":    false,
        "<<":   false,
        ">>":   false,
        "^":    true,    
        "*":    false,
        "/":    false,
        "+":    false,
        "-":    false,
        // "|":    false,
        ":":    true,
    ];
    ftable = generateFunctionTable();
}

bool isWordInitial(T)(T c) { return isAlpha(c) || c == '_'; }
bool isWordBody(T)(T c) { return isAlphaNum(c) || c == '_'; }

// TODO: stream tokens
Token[] tokenize(string code) {
    TokenType lastSignificantType;
    Token[] build;
    for(uint i = 0; i < code.length; i++) {
        Token cur;
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
            cur.type = TokenType.Reference;
            cur.raw ~= code[i++]; // skip initial $
            while(i < code.length && isDigit(code[i])) {
                cur.raw ~= code[i++];
            }
            i--;
        }
        else if(isWhite(code[i])) {
            // TODO: collapse strings of consecutive whitespace
            cur.type = TokenType.Whitespace;
            cur.raw ~= code[i];
        }
        else if(code[i] == '(') {
            cur.type = TokenType.LeftParen;
            cur.raw ~= code[i];
        }
        else if(code[i] == ')') {
            cur.type = TokenType.RightParen;
            cur.raw ~= code[i];
        }
        else if(code[i] == '[') {
            cur.type = TokenType.LeftFold;
            cur.raw ~= code[i];
        }
        else if(code[i] == ']') {
            cur.type = TokenType.RightFold;
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
                    // determine unary or binary
                    cur.type = TokenType.Operator;
                    if(lastSignificantType == TokenType.Unknown
                    || lastSignificantType == TokenType.LeftParen
                    || lastSignificantType == TokenType.Operator
                    || lastSignificantType == TokenType.UnaryOperator) {
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
        }
        build ~= cur;
    }
    return build;
}

Token[] shunt(Token[] tokens) {
    Token[] outputQueue;
    Token[][] queueStack;
    Token[] opStack;
    
    foreach(tok; tokens) {
        final switch(tok.type) {
            case TokenType.Unknown:
                assert(0, "Unexpected Unknown token: " ~ to!string(tok));
            
            case TokenType.Whitespace:
            case TokenType.Comment:
                // ignore whitespace & comments
                break;
            
            case TokenType.Integer:
            case TokenType.Word:
            case TokenType.Reference:
                outputQueue ~= tok;
                break;
            
            case TokenType.Operator:
                int myPrecedence = precedence[tok.raw];
                bool isRightAssociative = rightAssociative[tok.raw];
                while(
                    !opStack.empty && !opStack.back.leftParen
                    && (
                        opStack.back.unary
                        || (
                            isRightAssociative
                                ? precedence[opStack.back.raw] >  myPrecedence
                                : precedence[opStack.back.raw] >= myPrecedence
                        )
                        // TODO: right associative? (exclude == case)
                    )
                ) {
                    outputQueue ~= opStack.back;
                    opStack.popBack;
                }
                opStack ~= tok;
                break;
            
            case TokenType.UnaryOperator:
                opStack ~= tok;
                break;
            
            case TokenType.LeftParen:
                opStack ~= tok;
                break;
            
            case TokenType.RightParen:
                while(!opStack.empty && opStack.back.type != TokenType.LeftParen) {
                    outputQueue ~= opStack.back;
                    opStack.popBack;
                }
                assert(!opStack.empty && opStack.back.type == TokenType.LeftParen,
                    "Unbalanced right parenthesis");
                opStack.popBack;
                // TODO:? handle function calls
                break;
            
            case TokenType.LeftFold:
                opStack ~= tok;
                queueStack ~= outputQueue;
                outputQueue = [];
                break;
            
            case TokenType.RightFold:
                while(!opStack.empty && opStack.back.type != TokenType.LeftFold) {
                    outputQueue ~= opStack.back;
                    opStack.popBack;
                }
                assert(!opStack.empty && opStack.back.type == TokenType.LeftFold,
                    "Unbalanced right parenthesis");
                opStack.popBack;
                tok.children = outputQueue;
                outputQueue = queueStack.back;
                queueStack.popBack;
                opStack ~= tok;
                // TODO:? handle function calls
                break;
        }
    }
    
    while(!opStack.empty) {
        assert(!opStack.back.leftParen, "Unbalanced left parenthesis");
        outputQueue ~= opStack.back;
        opStack.popBack;
    }
    
    return outputQueue;
}

SequenceFunction interpret(string code) {
    return code.tokenize.shunt.interpret([BigInt(0), BigInt(1)]);
}

SequenceFunction interpret(string code, BigInt[] referenceData) {
    return code.tokenize.shunt.interpret(referenceData);
}

alias Atom = SumType!(SequenceFunction, BigInt);
SequenceFunction callableFrom(Atom atom) {
    return atom.match!(
        (SequenceFunction fn) => fn,
        (BigInt i) => (BigInt _) => i,
    );
}

BigInt execOp(alias op)(BigInt a, BigInt b) {
    static if(op == "/") {
        assert(b != 0, "Dividing by zero");
    }
    static if(op == "^") {
        return bpow(a, b);
    }
    else {
        return mixin("a " ~ op ~ " b");
    }
}


Atom foldFor(Atom a, Token[] children) {
    SequenceFunction fn = a.match!(
        (BigInt _) => assert(0, "Cannot fold an integer"),
        (SequenceFunction a) => a,
    );
    return Atom(unaryRecursiveMemo((BigInt n, This) {
        if(n <= 0) {
            return fn(n);
        }
        BigInt[] args = [ This(n - 1), fn(n) ];
        auto subFn = children.interpret(args);
        return subFn(BigInt(0));
    }));
}

SequenceFunction interpret(Token[] shunted, BigInt[] referenceData) {
    Atom[] stack;
    foreach(tok; shunted) {
        InterpretSwitch:
        final switch(tok.type) {
            case TokenType.Unknown:
            case TokenType.LeftParen:
            case TokenType.LeftFold:
            case TokenType.RightParen:
            case TokenType.Comment:
                assert(0, "Unexpected token: " ~ to!string(tok));
            
            case TokenType.Whitespace:
                // ignore whitespace
                break;
                
            case TokenType.Integer:
                stack ~= Atom(BigInt(tok.raw));
                break;
            
            case TokenType.Word:
                string properName = normalizeSequenceName(tok.raw);
                stack ~= Atom(ftable[properName]);
                break;
            
            case TokenType.Reference:
                int index = to!int(tok.raw[1..$]);
                assert(index >= 0 && index < referenceData.length, "Out of bounds reference index");
                stack ~= Atom(referenceData[index]);
                break;
            
            case TokenType.UnaryOperator:
                if(tok.raw == "-") {
                    Atom a = stack.back;
                    stack.popBack;
                    stack ~= a.match!(
                        (BigInt a) => Atom(-a),
                        (SequenceFunction fn) => Atom((BigInt n) => -fn(n)),
                    );
                }
                else {
                    assert(0, "Unknown unary operator: " ~ tok.raw);
                }
                break;
            
            case TokenType.RightFold:
                Atom a = stack.back;
                stack.popBack;
                stack ~= foldFor(a, tok.children);
                break;
            
            case TokenType.Operator:
                static foreach(simpleOp; ["+", "-", "*", "/", "^"]) {
                    if(tok.raw == simpleOp) {
                        Atom b = stack.back;
                        stack.popBack;
                        Atom a = stack.back;
                        stack.popBack;
                        stack ~= match!(
                            (BigInt a, BigInt b) => Atom(execOp!simpleOp(a, b)),
                            // closure for (a, b)
                            (_1, _2) => Atom(((SequenceFunction a, SequenceFunction b) =>
                                (BigInt n) => execOp!simpleOp(a(n), b(n))
                            )(a.callableFrom, b.callableFrom))
                        )(a, b);
                        break InterpretSwitch;
                    }
                }
                switch(tok.raw) {
                    case "@":
                        Atom index = stack.back;
                        stack.popBack;
                        SequenceFunction fn = stack.back.callableFrom;
                        stack.popBack;
                        stack ~= index.match!(
                            (BigInt i) => Atom(fn(i)),
                            (SequenceFunction g) => 
                                // closure for fn
                                ((SequenceFunction fn) =>
                                    Atom((BigInt n) => fn(g(n)))
                                )(fn),
                        );
                        break;
                    
                    case ":":
                        Atom sequence = stack.back;
                        stack.popBack;
                        Atom prepend = stack.back;
                        stack.popBack;
                        stack ~= match!(
                            (BigInt a, SequenceFunction seq) => Atom(
                                (BigInt n) => n == 0 ? a : seq(n - 1)
                            ),
                            (_1, _2) => assert(0, "Cannot prepend")
                        )(prepend, sequence);
                        break;
                    
                    default:
                        assert(0, "Unimplemented operator: " ~ tok.raw);
                }
                break;
        }
    }
    if(stack.empty) {
        return callableFrom(Atom(BigInt(0)));
    }
    return callableFrom(stack.back);
}
