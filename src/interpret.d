module plis.interpret;

import plis.impl;
import plis.debugger;
import plis.parse;
import plis.shunt;

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

FunctionTable ftable;
static this() {
    ftable = generateFunctionTable();
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

string hashToString(Token[][string] hash) {
    string rep = "[ ";
    foreach(key, value; hash) {
        rep ~= key ~ ": [" ~ value.map!(t => t.raw).join(" ") ~ "], ";
    }
    return rep[0..$-2] ~ " ]";
}

struct StateInformation {
    Atom[] referenceData;
    Token[][string] functionWords;
    Atom[string] variableWords;
    
    StateInformation dup() {
        StateInformation next;
        next.referenceData = referenceData.dup;
        // TODO: deep dup?
        next.functionWords = functionWords.dup;
        next.variableWords = variableWords.dup;
        return next;
    }
    
    Atom getReferenceData(T)(T index) {
        assert(index >= 0 && index < referenceData.length, "Out of bounds reference index");
        return referenceData[index];
    }
    
    Atom getVariable(string name) {
        auto ptr = name in variableWords;
        assert(ptr, "Undefined variable `" ~ name ~ "`");
        return *ptr;
    }
    
    string toString() {
        return "StateInformation("
             ~ referenceData.to!string ~ ", "
             ~ functionWords.hashToString ~ ", "
             ~ variableWords.to!string
             ~ ")";
    }
}

Token[][string] standardLibrary;
static this() {
    string[string] codeLib = [
        "print": "%$0;%10;$0",
        "catat": "$mask(A7@(A1477/$1))mask*$0.$1+(1-mask)*$2>>$1",
        "digits": "$size(A055642@$0)($0/A011557%10)@(size-A27).size",
        "strlen": "@(A7@$0)@0",
    ];
    foreach(key, value; codeLib) {
        standardLibrary[key] = value.tokenize.shunt;
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
    Atom[] stack;
    foreach(tok; shunted) {
        debugPlis("interpret", "state = ", state);
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
            case TokenType.Break:
                assert(0, "Unexpected token: " ~ to!string(tok));
            
            case TokenType.Whitespace:
                // ignore whitespace
                break;
                
            case TokenType.Integer:
                stack ~= Atom(BigInt(tok.raw));
                break;
            
            case TokenType.String:
                string inner = tok.raw[1..$-1];
                stack ~= Atom((BigInt n) =>
                    BigInt(n < inner.length ? inner[n.to!uint].to!int : 0));
                break;
            
            case TokenType.WordReference:
                state.functionWords[tok.raw[1..$]] = tok.children;
                break;
            
            case TokenType.VariableSet:
                debugPlis("interpret", "-- setting variable " ~ tok.raw ~ " --");
                auto value = interpret(tok.children, state);
                state.variableWords[tok.raw[1..$]] = value;
                debugPlis("interpret",
                    "set value of " ~ tok.raw ~ " to " ~ value.to!string);
                break;
            
            case TokenType.Word:
                auto fword = tok.raw in state.functionWords;
                auto vword = tok.raw in state.variableWords;
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
                else if(vword) {
                    debugPlis("interpret", "retrieving value of variable $" ~ tok.raw);
                    stack ~= *vword;
                }
                else {
                    // sequence reference
                    string properName = normalizeSequenceName(tok.raw);
                    auto seqfn = properName in ftable;
                    assert(seqfn, "Unknown/unimplemented sequence: " ~ properName);
                    stack ~= Atom(*seqfn);
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
                    
                    // clamp sequence
                    case ".":
                        Atom b = stack.back;
                        stack.popBack;
                        Atom a = stack.back;
                        stack.popBack;
                        stack ~= match!(
                            // n.seq
                            (BigInt a, SequenceFunction seq) =>
                                assert(0, "n.seq is unimplemented"),
                            // seq.n - only first n
                            (SequenceFunction seq, BigInt b) =>
                                Atom((BigInt n) => n < b ? seq(n) : BigInt(0)),
                            (_1, _2) => assert(0, "Cannot clamp")
                        )(a, b);
                        break;
                        
                    // shift sequence right
                    case ">>":
                        Atom by = stack.back;
                        stack.popBack;
                        BigInt amt = by.match!(
                            (BigInt a) => a,
                            (SequenceFunction fn) => assert(0, "Cannot shift by a sequence"),
                        );
                        Atom seq = stack.back;
                        stack.popBack;
                        stack ~= seq.match!(
                            (BigInt _) => assert(0, "Cannot right shift integer"),
                            (SequenceFunction fn) => Atom((BigInt n) => 
                                fn(max(BigInt(0), n - amt))),
                        );
                        break;
                        
                    // shift sequence left
                    case "<<":
                        Atom by = stack.back;
                        stack.popBack;
                        BigInt amt = by.match!(
                            (BigInt a) => a,
                            (SequenceFunction fn) => assert(0, "Cannot shift by a sequence"),
                        );
                        Atom seq = stack.back;
                        stack.popBack;
                        stack ~= seq.match!(
                            (BigInt _) => assert(0, "Cannot left shift integer"),
                            (SequenceFunction fn) => Atom((BigInt n) => 
                                fn(max(BigInt(0), n + amt))),
                        );
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
