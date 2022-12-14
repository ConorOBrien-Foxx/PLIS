module plis.main;

import plis.debugger;
import plis.impl;
import plis.interpret;
import plis.parse;

import std.algorithm.iteration : map;
import std.bigint;
import std.conv;
import std.file : read;
import std.getopt;
import std.range : array;
import std.stdio;
import std.sumtype;

void main(string[] args) {
    bool autoGolf, encode, decode, help, infinite;
    string lowerIndex = "0";
    string upperIndex = "20";
    string fileName;
    auto helpInformation = getopt(
        args,
        std.getopt.config.bundling,
        "e|encode", "Encode/Decode a function name", &encode,
        "g|golf", "Auto golfs the supplied code", &autoGolf,
        // TODO: debug filter for particular source(s)
        "d|debug", "Show debugging statements", &debugging,
        "h|help", "Prints help dialogue", &help,
        "l|lower", "Sets lower index", &lowerIndex,
        "u|upper", "Sets upper index", &upperIndex,
        "i|infinite", "Prints values starting at lower indefinitely", &infinite,
        "f|file", "Read code from a file", &fileName,
    );

    if(help || helpInformation.helpWanted) {
        defaultGetoptPrinter("Help:", helpInformation.options);
    }
    
    if(encode) {
        foreach(arg; args[1..$]) {
            write(arg, " <-> ");
            string norm = normalizeSequenceName(arg);
            write(norm, " <-> ");
            int val = norm[1..$].to!int;
            writeln(encodeSequenceNumber(val));
        }
        return;
    }
    
    string code;
    uint dataStart;
    if(fileName) {
        code = fileName.read.to!string;
        dataStart = 1;
    }
    else {
        code = args[1];
        dataStart = 2;
    }
    
    StateInformation state;
    state.referenceData = args[dataStart..$]
        .map!BigInt
        .map!Atom
        .array;
    state.functionWords = standardLibrary;
    
    if(autoGolf) {
        bool[string] functionWords;
        foreach(key; standardLibrary.keys) {
            functionWords[key] = true;
        }
        foreach(tok; code.tokenize) {
            if(tok.type == TokenType.Word
            && isANumber(tok.raw)
            && !(tok.raw in functionWords)) {
                write(encodeSequenceNumber(
                    normalizeSequenceName(tok.raw)[1..$].to!int
                ));
            }
            else if(tok.type != TokenType.Whitespace
                 && tok.type != TokenType.Comment) {
                write(tok.raw);
            }
        }
        writeln();
        return;
    }
    
    auto result = code.interpret(state);
    result.match!(
        (BigInt n) => writeln(n),
        (SequenceFunction fn) {
            BigInt index = lowerIndex;
            BigInt max = upperIndex;
            while(infinite || index <= max) {
                write(fn(index), " ");
                index++;
            }
            writeln();
        },
    );
}
