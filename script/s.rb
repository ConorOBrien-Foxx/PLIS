# investigation: upperbound of precision for nikantha series
arr = []
upper = 3684031
20.upto(30) { |i|
    print "#{i}/#{upper}...\r"
    x = %x(./plis -u#{upper} -- "10^#{i}*3:DqD/1:(_FM*PeY)").lines.last.split.index("0")
    if x.nil?
        upper *= 2
        redo
    end
    arr << x
}
puts
p arr
