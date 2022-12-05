module plis.shunt;

import plis.debugger;
import plis.parse;
import plis.interpret : standardLibrary;

import std.conv;
import std.range;

Token[] shunt(Token[] tokens) {
    Token[] outputQueue;
    Token[][] queueStack;
    Token[] opStack;
    bool[string] functionWords;
    // bool[string] variableWords;
    int[] arities = [];
    
    foreach(key; standardLibrary.keys) {
        functionWords[key] = true;
    }
    
    bool lastNeedsLeftParenthesis = false;
    
    void simpleFlush(bool enforce = false) {
        while(!opStack.empty && !opStack.back.leftParen) {
            assert(!enforce || !opStack.back.leftParen,
                "Unclosed left parenthesis " ~ opStack.back.raw);
            outputQueue ~= opStack.back;
            opStack.popBack;
        }
    }
    
    foreach(tok; tokens) {
        debugPlis("shunt", "token = ", tok);
        debugPlis("shunt", "opstack = ", opStack);
        debugPlis("shunt", "outqueue = ", outputQueue);
        debugPlis("shunt", "queueStack = ", queueStack);
        debugPlis("shunt");
        
        assert(!lastNeedsLeftParenthesis || tok.type == TokenType.LeftParen,
            "Expected left parenthesis following function/definition");
        lastNeedsLeftParenthesis = false;
        
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
                simpleFlush();
                break;
            
            case TokenType.String:
            case TokenType.Integer:
            case TokenType.Reference:
                outputQueue ~= tok;
                break;
            
            case TokenType.WordReference:
                functionWords[tok.raw[1..$]] = true;
                lastNeedsLeftParenthesis = true;
                opStack ~= tok;
                break;
            
            case TokenType.VariableSet:
                // variableWords[tok.raw[1..$]] = true;
                lastNeedsLeftParenthesis = true;
                opStack ~= tok;
                break;
                
            case TokenType.Word:
                if(tok.raw in functionWords) {
                    opStack ~= tok;
                    lastNeedsLeftParenthesis = true;
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
                opStack ~= tok;
                break;
            
            case TokenType.UnaryOperator:
                opStack ~= tok;
                break;
            
            case TokenType.Break:
                simpleFlush();
                break;
            
            case TokenType.LeftParen:
                opStack ~= tok;
                queueStack ~= outputQueue;
                outputQueue = [];
                // TODO: handle 0-arg functions
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
                    else if(opStack.back.type == TokenType.VariableSet) {
                        debugPlis("shunt", "-- variable set encountered --");
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
                queueStack.popBack;
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
    
    simpleFlush(true);
    debugPlis("shunt", "content after shunt:");
    debugPlis("shunt", "opstack = ", opStack);
    debugPlis("shunt", "outqueue = ", outputQueue);
    debugPlis("shunt", "queueStack = ", queueStack);
    
    return outputQueue;
}
