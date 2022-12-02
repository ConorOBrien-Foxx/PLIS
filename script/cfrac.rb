# investigation: fraction integer representation
def continued_frac(r)
    i = r.floor
    f = r - i
    if f.zero?
        [i]
    else
        [i, *continued_frac(1 / f)]
    end
end

def inverse_cwtree(r)
    cf = continued_frac r
    if cf.size.even?
        # sequence length must be odd for this to work
        # identity: 1/x <=> 1/((x-1)+1/1)
        # effect: [... X Y] <=> [... X (Y-1) 1]
        cf[-1] -= 1
        cf << 1
    end
    cf.flat_map.with_index { |amt, i|
        # run length decode alternating bits
        [(i + 1) % 2] * amt
    }.map.with_index { |bit, i|
        bit * 2**i
    }.sum
end

p continued_frac 53r/37
p inverse_cwtree 3r/4
p inverse_cwtree 4r/3
p inverse_cwtree 5r/8
p inverse_cwtree 1r/12144