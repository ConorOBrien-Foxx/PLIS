module plis.impl;

import plis.debugger;

import std.algorithm;
import std.bigint;
import std.conv : to;
import std.functional;
import std.range;

alias SequenceFunction = BigInt delegate(BigInt);

BigInt repeatTake(T)(T arr, BigInt index) {
    return BigInt(arr[to!uint(index % arr.length)]);
}

BigInt[] divisors(BigInt n) {
    BigInt[] res;
    foreach(k; BigInt(1)..n+1) {
        if(n % k == 0) {
            res ~= k;
        }
    }
    return res;
}

BigInt bpow(BigInt base, BigInt p) {
    if(p == 0) return BigInt(1);
    if(base == 0) return BigInt(0);
    BigInt res = base;
    foreach(k; BigInt(1)..p) {
        res *= base;
    }
    return res;
}

auto unaryMemo(alias fn)(BigInt n) {
    alias seq = unaryFun!fn;
    static BigInt[BigInt] cache;
    
    auto has = n in cache;
    if(has) {
        return *has;
    }
    else {
        return cache[n] = seq(n);
    }
}

static uint uuid = 0;
auto unaryRecursiveMemo(BigInt delegate(BigInt, SequenceFunction) seq) {
    BigInt[BigInt] cache;
    auto myUuid = "rec@" ~ uuid++.to!string;
    
    BigInt rec(BigInt n) {
        debugPlis(myUuid, "-- start --");
        debugPlis(myUuid, "cache = ", cache);
        auto has = n in cache;
        if(has) {
            return *has;
        }
        else {
            BigInt result = seq(n, (BigInt n) => rec(n));
            cache[n] = result;
            return result;
        }
    }
    return (BigInt n) => rec(n);
}

BigInt Fibonacci(alias s)(BigInt n) {
    BigInt[] seed = s.map!BigInt.array;
    auto fn = unaryRecursiveMemo((BigInt n, This) {
        if(n < seed.length) {
            return seed[to!uint(n)];
        }
        else {
            BigInt sum = 0;
            foreach(i; 0..seed.length) {
                sum += This(n - i - 1);
            }
            return sum;
        }
    });
    return fn(n);
}

BigInt prependCons(alias start, alias fn)(BigInt n) {
    alias seq = unaryFun!fn;
    if(n < start.length) {
        return BigInt(start[to!uint(n)]);
    }
    else {
        return seq(n - start.length);
    }
}

BigInt plusOne(alias fn)(BigInt n) {
    alias seq = unaryFun!fn;
    return seq(n + 1);
}

// implementing equations (7) and (8) from
// https://mathworld.wolfram.com/EulerTransform.html
// given fn is assumed to be 0-indexed
// outputs a 0-indexed sequence
BigInt eulerTransform(alias start, alias fn)(BigInt n) {
    alias seq = unaryFun!fn;
    static BigInt[BigInt] cache;
    
    // helper functions
    BigInt c(BigInt n) {
        return divisors(n)
            .map!(d => d * seq(d - 1))
            .sum;
    }
    
    auto recursive = unaryRecursiveMemo((BigInt n, This) {
        if(n == 1) {
            return BigInt(start);
        }
        BigInt val = c(n);
        val += iota(BigInt(1), n)
            .map!(k => c(k) * This(n - k))
            .sum;
        val /= n;
        return val;
    });
    
    // n + 1 to offset our indices to take 0-indexed
    return recursive(n + 1);
}

BigInt eulerTransform(alias fn)(BigInt n) {
    return eulerTransform!(1, fn)(n);
}

/** misc non-trivial **/
SequenceFunction A002487;
static this() {
    A002487 = unaryRecursiveMemo((BigInt n, This) {
        if(n <= 0)      return BigInt(0);
        if(n == 1)      return BigInt(1);
        if(n % 2 == 0)  return This(n / 2);
        else            return This(n / 2) + This(n / 2 + 1);
    });
}
// digit length
BigInt A055642(BigInt n) { return BigInt(n.to!string.length); }

/** eulerTransform **/
alias A000726 = eulerTransform!(a => [1,1,0].repeatTake(a));
alias A005928 = prependCons!([1], eulerTransform!(-3, a => [-3,-3,-2].repeatTake(a)));
alias A001970 = eulerTransform!(eulerTransform!"1");
alias A034691 = eulerTransform!A000079;
// TODO: does my eulerTransform correctly account for 0 at start of seq?
alias A166861 = prependCons!([1], eulerTransform!(plusOne!A000045));
alias A000335 = eulerTransform!(plusOne!A000292);
alias A073592 = prependCons!([1], eulerTransform!(-1, plusOne!A001489));

// lucas numbers
alias A000032 = Fibonacci!([2, 1]);
// classical fibonacci
alias A000045 = Fibonacci!([0, 1]);

/** trivial data modifiers **/
// positive integers, offset=1,2
BigInt A000027(BigInt index) { return index; }
// non-negative integers, offset=0,3
BigInt A001477(BigInt index) { return index; }
// a(n)=2-n
BigInt A022958(BigInt index) { return 2 - index; }
// a(n)=40-n
BigInt A022996(BigInt index) { return 40 - index; }
// a(n)=-n
BigInt A001489(BigInt index) { return -index; }

/** multiplication/division **/
// a(n)=2n
BigInt A005843(BigInt index) { return index * 2; }
// a(n)=3n
BigInt A008585(BigInt index) { return index * 3; }
// a(n)=2^n
BigInt A000079(BigInt index) { return bpow(BigInt(2), index); }
// a(n)=n*(n+1)*(2n+1)/6 ; square pyramidal numbers
BigInt A000330(BigInt index) { return index * (index + 1) * (2 * index + 1) / 6; }
// a(n)=n*(n+1)*(n+2)/6 ; tetrahedral numbers
BigInt A000292(BigInt index) { return index * (index + 1) * (index + 2) / 6; }
// a(n)=(2n+2)*(2n+3)*(2n+4)
BigInt A069074(BigInt index) { return 24 * A000330(index + 1); }

/** addition/subtraction **/
// a(n)=n-1
BigInt A023443(BigInt index) { return index - 1; }
// a(n)=n+1
BigInt A020725(BigInt index) { return index + 1; }

/** mod/repeat **/
alias A136619 = prependCons!([1],
    (BigInt index) => [1, 4, 2].repeatTake(index));
//// trivial sequences
alias A000007 = prependCons!([1], A000004);
// a(n)=0
BigInt A000004(BigInt index) { return BigInt(0); }
// a(n)=1
BigInt A000012(BigInt index) { return BigInt(1); }
// a(n)=4
BigInt A010709(BigInt index) { return BigInt(4); }
// a(n)=n%2 ; repeat [0,1]
BigInt A000035(BigInt index) { return BigInt(index % 2); }
// a(n)=1-n%2 ; repeat [1,0]
BigInt A059841(BigInt index) { return BigInt(1 - index % 2); }
// a(n)=1+n%2 ; repeat [1,2]
BigInt A000034(BigInt index) { return BigInt(1 + index % 2); }
// a(n)=(-1)^n ; repeat [1,-1]
BigInt A033999(BigInt index) { return [1, -1].repeatTake(index); }
// a(n)=repeat (1,3)
BigInt A010684(BigInt index) { return [1, 3].repeatTake(index); }
// a(n)=repeat (1,4)
BigInt A010685(BigInt index) { return [1, 4].repeatTake(index); }
// a(n)=repeat [0,2]
BigInt A010673(BigInt index) { return [0, 2].repeatTake(index); }
// a(n)=repeat (0,3)
BigInt A010674(BigInt index) { return [0, 3].repeatTake(index); }
// a(n)=repeat (1,7)
BigInt A010688(BigInt index) { return [1, 7].repeatTake(index); }
// a(n)=repeat [4,2]
BigInt A105397(BigInt index) { return [4, 2].repeatTake(index); }
// a(n)=repeat [1,-1,0]
BigInt A049347(BigInt index) { return [1, -1, 0].repeatTake(index); }
// a(n)=repeat [0,1,1]
BigInt A011655(BigInt index) { return [0, 1, 1].repeatTake(index); }
// a(n)=repeat [1,1,-2]
BigInt A061347(BigInt index) { return [1, 1, -2].repeatTake(index); }
// a(n)=repeat [0,1,-1]
BigInt A102283(BigInt index) { return [0, 1, -1].repeatTake(index); }
// a(n)=repeat [1,2,2]
BigInt A130196(BigInt index) { return [1, 2, 2].repeatTake(index); }
// a(n)=repeat [1,2,1]
BigInt A131534(BigInt index) { return [1, 2, 1].repeatTake(index); }
// a(n)=repeat [1,2,3]
BigInt A010882(BigInt index) { return [1, 2, 3].repeatTake(index); }
// a(n)=repeat [1,4,2]
BigInt A153727(BigInt index) { return [1, 4, 2].repeatTake(index); }
// a(n)=repeat [0,2,1]
BigInt A080425(BigInt index) { return [0, 2, 1].repeatTake(index); }
// a(n)=repeat [3,3,1]
BigInt A144437(BigInt index) { return [3, 3, 1].repeatTake(index); }
// a(n)=repeat [1,-2,1]
BigInt A131713(BigInt index) { return [1, -2, 1].repeatTake(index); }
// a(n)=repeat [1,-2,1]
BigInt A130784(BigInt index) { return [1, 3, 2].repeatTake(index); }
// a(n)=repeat [1,3,3]
BigInt A169609(BigInt index) { return [1, 3, 3].repeatTake(index); }
// a(n)=repeat [1,1,-1]
BigInt A131561(BigInt index) { return [1, 1, -1].repeatTake(index); }
// a(n)=repeat [3,2,2]
BigInt A052901(BigInt index) { return [3, 2, 2].repeatTake(index); }
// a(n)=repeat [15,24,18]
BigInt A274339(BigInt index) { return [15, 24, 18].repeatTake(index); }
// a(n)=repeat [1,8,9]
BigInt A073636(BigInt index) { return [1, 8, 9].repeatTake(index); }
// a(n)=repeat [0,1,3]
BigInt A101000(BigInt index) { return [0, 1, 3].repeatTake(index); }
// a(n)=repeat [2,5,8]
BigInt A131598(BigInt index) { return [2, 5, 8].repeatTake(index); }
// a(n)=repeat [1,1,2]
BigInt A177702(BigInt index) { return [1, 1, 2].repeatTake(index); }
// a(n)=repeat [2,-1,3]
BigInt A131756(BigInt index) { return [2, -1, 3].repeatTake(index); }
// a(n)=repeat [1,2,-3]
BigInt A132677(BigInt index) { return [1, 2, -3].repeatTake(index); }
// a(n)=repeat [1,4,1]
BigInt A146325(BigInt index) { return [1, 4, 1].repeatTake(index); }
// a(n)=repeat [4,1,4]
BigInt A173259(BigInt index) { return [4, 1, 4].repeatTake(index); }
// a(n)=repeat [5,4,3]
BigInt A164360(BigInt index) { return [5, 4, 3].repeatTake(index); }
// a(n)=repeat [1,0,0]
BigInt A079978(BigInt index) { return [1, 0, 0].repeatTake(index); }



/**
todo:
https://oeis.org/A057531
http://oeis.org/A000726
http://oeis.org/A030203
http://oeis.org/search?q=%22period%203%22&start=120&fmt=short
http://oeis.org/A000726

https://en.wikipedia.org/wiki/Binomial_transform

https://tio.run/##ZY1Pi8IwFMTP@ike9ZLQkFTqfxHpuhcvy8J6Mx5iG7SIsbyksGLz2bsp9rYw8AZmfvOwPj/btqqdhZ/D5/6Lo1YFt7kyRJBMFjHlMepKKwdEHnm8ladGku5SKii/qwpe0BgG2EAkBChi6KYHRi/kF1ufiZBWsCiiXpqP8rI3XWQ86X1pCv1LwwxqV6PpMM/fEwd10@Sdr8FHvm2z8WySzhIYDL41lo8C0hX0745TBhMG6YnDMEvmy@V8EWq7q0KVu1C2rszhPzVmkAQF6g8

*/