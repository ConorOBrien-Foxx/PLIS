module plis.interpret;

import plis.impl;
import plis.debugger;

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
    Integer, Whitespace,
    Comma,
    LeftParen, RightParen,
    LeftFold, RightFold,
    LeftMap, RightMap,
}
struct Token {
    TokenType type;
    string raw;
    Token[] children;
    uint arity;
    
    string toString() {
        return "Token(" ~ to!string(type) ~ ", " ~ raw ~ ", " ~ children.to!string ~ ")";
    }
    
    bool unary() {
        return type == TokenType.UnaryOperator
            || type == TokenType.RightFold
            || type == TokenType.RightMap;
    }
    
    bool leftParen() {
        return type == TokenType.LeftParen
            || type == TokenType.LeftFold
            || type == TokenType.LeftMap;
    }
    
    bool operator() {
        return unary
            || type == TokenType.Operator;
    }
}

// sorted by greedy precedence (i.e. longest first)
static string[] operators = [
    "<<", ">>",
    "*", "+", "-", "/", "%", "@", ":", "^",
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
        "%":    7,
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
        "%":    false,
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
            assert(i < code.length, "Expected number after `$`");
            cur.raw ~= code[i++]; // skip initial $
            while(i < code.length && isDigit(code[i])) {
                cur.raw ~= code[i++];
            }
            i--;
        }
        else if(code[i] == '&') {
            cur.type = TokenType.WordReference;
            cur.raw ~= code[i++]; // skip iniitial &
            assert(i < code.length, "Expected word after `&`");
            assert(isWordInitial(code[i]), "Cannot start identifier with " ~ code[i]);
            while(i < code.length && isWordBody(code[i])) {
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
                    || lastSignificantType == TokenType.Comma
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
    bool[string] functionWords;
    int[] arities = [];
    
    foreach(tok; tokens) {
        debugPlis("shunt", "opstack = ", opStack);
        debugPlis("shunt", "outqueue = ", outputQueue);
        debugPlis("shunt");
        final switch(tok.type) {
            case TokenType.Unknown:
                assert(0, "Unexpected Unknown token: " ~ to!string(tok));
            
            case TokenType.Whitespace:
            case TokenType.Comment:
                // ignore whitespace & comments
                break;
            
            case TokenType.Comma:
                assert(!arities.empty, "Comma cannot appear at top level");
                arities.back++;
                break;
            
            case TokenType.Integer:
            case TokenType.Reference:
                outputQueue ~= tok;
                break;
            
            case TokenType.WordReference:
                functionWords[tok.raw[1..$]] = true;
                opStack ~= tok;
                break;
                
            case TokenType.Word:
                if(tok.raw in functionWords) {
                    opStack ~= tok;
                }
                else {
                    outputQueue ~= tok;
                }
                break;
                
            case TokenType.Operator:
                int myPrecedence = precedence[tok.raw];
                bool isRightAssociative = rightAssociative[tok.raw];
                while(
                    !opStack.empty && opStack.back.operator
                    && (
                        opStack.back.unary
                        || (
                            isRightAssociative
                                ? precedence[opStack.back.raw] >  myPrecedence
                                : precedence[opStack.back.raw] >= myPrecedence
                        )
                    )
                ) {
                    outputQueue ~= opStack.back;
                    opStack.popBack;
                }
                // TODO: handle function
                opStack ~= tok;
                break;
            
            case TokenType.UnaryOperator:
                opStack ~= tok;
                break;
            
            case TokenType.LeftParen:
                opStack ~= tok;
                queueStack ~= outputQueue;
                outputQueue = [];
                arities ~= 1;
                break;
            
            case TokenType.RightParen:
                while(!opStack.empty && opStack.back.type != TokenType.LeftParen) {
                    outputQueue ~= opStack.back;
                    opStack.popBack;
                }
                assert(!opStack.empty && opStack.back.type == TokenType.LeftParen,
                    "Unbalanced right parenthesis");
                opStack.popBack;
                if(!opStack.empty) {
                    if(opStack.back.type == TokenType.WordReference) {
                        debugPlis("shunt", "-- word reference encountered --");
                        opStack.back.children = outputQueue;
                        outputQueue = [ opStack.back ];
                        opStack.popBack;
                    }
                    else if(opStack.back.type == TokenType.Word) {
                        debugPlis("shunt", "-- function word encountered --");
                        opStack.back.arity = arities.back;
                        outputQueue ~= opStack.back;
                        opStack.popBack;
                    }
                }
                outputQueue = queueStack.back ~ outputQueue;
                arities.popBack;
                break;
            
            case TokenType.LeftFold:
            case TokenType.LeftMap:
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
                    "Unbalanced right bracket");
                opStack.popBack;
                tok.children = outputQueue;
                outputQueue = queueStack.back;
                queueStack.popBack;
                opStack ~= tok;
                break;
            
            case TokenType.RightMap:
                // TODO: condense & abstract behavior with above
                while(!opStack.empty && opStack.back.type != TokenType.LeftMap) {
                    outputQueue ~= opStack.back;
                    opStack.popBack;
                }
                assert(!opStack.empty && opStack.back.type == TokenType.LeftMap,
                    "Unbalanced right brace");
                opStack.popBack;
                tok.children = outputQueue;
                outputQueue = queueStack.back;
                queueStack.popBack;
                opStack ~= tok;
                break;
        }
    }
    
    while(!opStack.empty) {
        assert(!opStack.back.leftParen, "Unbalanced left parenthesis " ~ opStack.back.raw);
        outputQueue ~= opStack.back;
        opStack.popBack;
    }
    
    return outputQueue;
}

Atom interpret(string code) {
    StateInformation state;
    state.referenceData = [Atom(BigInt(0)), Atom(BigInt(1))];
    return code.tokenize.shunt.interpret(state);
}

Atom interpret(string code, StateInformation state) {
    return code.tokenize.shunt.interpret(state);
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

struct StateInformation {
    Atom[] referenceData;
    Token[][string] functionWords;
    
    StateInformation dup() {
        StateInformation next;
        next.referenceData = referenceData.dup;
        // TODO: deep dup?
        next.functionWords = functionWords.dup;
        return next;
    }
    
    Atom getReferenceData(T)(T index) {
        assert(index >= 0 && index < referenceData.length, "Out of bounds reference index");
        return referenceData[index];
    }
}

Atom foldFor(Atom a, Token[] children, StateInformation state) {
    SequenceFunction fn = a.match!(
        (BigInt _) => assert(0, "Cannot fold an integer"),
        (SequenceFunction a) => a,
    );
    return Atom(unaryRecursiveMemo((BigInt n, This) {
        debugPlis("cfold", "-- start --");
        if(n <= 0) {
            auto result = fn(n);
            debugPlis("cfold", n, " -> ", result);
            return result;
        }
        debugPlis("cfold", "children = ", children.map!(a => a.raw));
        debugPlis("cfold", "n = ", n, " ; getting args");
        Atom[] args = [ Atom(This(n - 1)), Atom(fn(n)) ];
        debugPlis("cfold", "args = ", args);
        auto state = state.dup;
        state.referenceData = args;
        auto subFn = children.interpret(state);
        auto result = subFn.callableFrom()(BigInt(0));
        debugPlis("cfold", args, " -> ", result);
        return result;
    }));
}

Atom mapFor(Atom a, Token[] children, StateInformation state) {
    SequenceFunction fn = a.match!(
        (BigInt _) => assert(0, "Cannot fold an integer"),
        (SequenceFunction a) => a,
    );
    return Atom((BigInt n) {
        debugPlis("map", "-- start --");
        auto value = fn(n);
        debugPlis("map", "children = ", children.map!(a => a.raw));
        auto state = state.dup;
        state.referenceData = [ Atom(value) ];
        auto subFn = children.interpret(state);
        auto result = subFn.callableFrom()(BigInt(0));
        debugPlis("map", n, " -> ", value, " -> ", result);
        return result;
    });
}

Atom trueIndicesFor(Atom a) {
    SequenceFunction fn = a.match!(
        (BigInt _) => assert(0, "Cannot fold an integer"),
        (SequenceFunction a) => a,
    );
    
    BigInt[] cachedList;
    BigInt pointer = 0;
    return Atom((BigInt n) {
        assert(n >= 0, "Cannot index by negative value");
        BigInt value;
        // will not run if index n is present in cache
        while(n >= cachedList.length) {
            // find one entry
            while((value = fn(pointer)) == 0) {
                pointer++;
            }
            // and add it to the list
            cachedList ~= pointer;
            pointer++;
        }
        return cachedList[n.to!uint];
    });
}

Atom interpret(Token[] shunted, StateInformation state) {
    debugPlis("interpret", "-- start --");
    debugPlis("interpret", "state = ", state);
    Atom[] stack;
    foreach(tok; shunted) {
        debugPlis("interpret", "`", tok.raw, "` ",
            tok.children.map!(a => a.raw).join(" "),
            " | ", stack);
        InterpretSwitch:
        final switch(tok.type) {
            case TokenType.Unknown:
            case TokenType.LeftFold:
            case TokenType.LeftMap:
            case TokenType.LeftParen:
            case TokenType.RightParen:
            case TokenType.Comment:
            case TokenType.Comma:
                assert(0, "Unexpected token: " ~ to!string(tok));
            
            case TokenType.Whitespace:
                // ignore whitespace
                break;
                
            case TokenType.Integer:
                stack ~= Atom(BigInt(tok.raw));
                break;
            
            case TokenType.WordReference:
                state.functionWords[tok.raw[1..$]] = tok.children;
                break;
            
            case TokenType.Word:
                auto fword = tok.raw in state.functionWords;
                if(fword) {
                    // function call
                    auto innerState = state.dup;
                    auto arity = tok.arity;
                    debugPlis("interpret", "calling function ", tok.raw, " with ", arity, " arg(s)");
                    innerState.referenceData = stack[$-arity..$];
                    stack.popBackN(arity);
                    stack ~= interpret(*fword, innerState);
                    break;
                }
                else {
                    // sequence reference
                    string properName = normalizeSequenceName(tok.raw);
                    stack ~= Atom(ftable[properName]);
                }
                break;
            
            case TokenType.Reference:
                int index = to!int(tok.raw[1..$]);
                stack ~= state.getReferenceData(index);
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
                // indices where true
                else if(tok.raw == "@") {
                    Atom a = stack.back;
                    stack.popBack;
                    stack ~= trueIndicesFor(a);
                }
                // output operator
                else if(tok.raw == "%") {
                    import std.stdio : write;
                    Atom a = stack.back;
                    a.match!(
                        (BigInt b) => write(b.to!char),
                        (SequenceFunction fn) {
                            BigInt index = 0;
                            BigInt cur;
                            while((cur = fn(index)) > 0) {
                                write(cur.to!char);
                                index++;
                            }
                        }
                    );
                }
                else {
                    assert(0, "Unknown unary operator: " ~ tok.raw);
                }
                break;
            
            case TokenType.RightFold:
                Atom a = stack.back;
                stack.popBack;
                stack ~= foldFor(a, tok.children, state);
                break;
            
            case TokenType.RightMap:
                Atom a = stack.back;
                stack.popBack;
                stack ~= mapFor(a, tok.children, state);
                break;
            
            case TokenType.Operator:
                static foreach(simpleOp; ["+", "-", "*", "/", "%", "^"]) {
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
    debugPlis("interpret", "-- done --");
    if(stack.empty) {
        return Atom(BigInt(0));
    }
    return stack.back;
    // if(stack.empty) {
        // return callableFrom(Atom(BigInt(0)));
    // }
    // return callableFrom(stack.back);
}
