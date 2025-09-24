#=
This program demonstrates that assignment of variables outside a function
can give rise to heap allocation even if their types are annotated
and have predictable size.

Julia version:  1.11.7
Platform:       MacOS Sequoia 15.6.1
Machine:        MacBook Pro with Apple M4 Max
=#


####### Functions performing stream processing

# The whole computation is more involved than necessary - on purpose!

const char_A::UInt8 = UInt8('A')
const char_Z::UInt8 = UInt8('Z')
const char_a::UInt8 = UInt8('a')
const char_z::UInt8 = UInt8('z')
const char_0::UInt8 = UInt8('0')
const char_9::UInt8 = UInt8('9')
const char_plus::UInt8 = UInt8('+')
const char_slash::UInt8 = UInt8('/')

"decode a Base64 character to a sextet of bits"
decode_char(char::UInt8)::UInt8 =
    char_A <= char <= char_Z ? char - char_A :
    char_a <= char <= char_z ? char - char_a + char_Z - char_A + 0x01 :
    char_0 <= char <= char_9 ? char - char_0 + char_z - char_a + char_Z - char_A + 0x02 :
    char == char_plus ? 0x3e :
    char == char_slash ? 0x3f :
    0x00  # error("Wrong character `$(Char(char))'!")

"""
Pack a sequence of sextets of bits into a sequence of octets in a
continuation-passing style (CPS): each octet is given as an argument to
the output function. Only complete octets are forwarded.

The input is also implemented in CPS: it is a function which is given a
continuation function as the only argument.
"""
function sextets2octets(input::Function, output::Function)::Nothing
    captured::UInt16 = UInt16(0)  # captured bits aligned left, first captured left-most
    bits::UInt8 = 0               # number of bits captured
    function pack(sextet::UInt8)::Nothing
        bits += 6
        captured |= (UInt16(sextet) << (16 - bits))   # <-- Allocation at each step!
        if bits >= 8
            output(UInt8(captured >> 8))
            captured <<= 8                            # <-- Allocation at each step!
            bits -= 8
        end
        return nothing
    end
    input(pack)
    return nothing
end

function chars_stateful2octets(chars, decoder::Function, output::Function)
    for char::UInt8 in Iterators.Stateful(chars)
        output(decoder(char))
    end
end


####### Get the data

using Downloads

io1 = IOBuffer()
Downloads.download("https://github.com/Martin-exp-z2/2025_09_22-Allocation_test/raw/refs/heads/main/chars1.txt", io1)
seekstart(io1)
chars1::Vector{UInt8} = read(io1)
close(io1)


####### Process the data and profile the evaluation

using Profile

chars1_decoded_stateful2octets(con) =
    chars_stateful2octets(chars1, decode_char, con)

discard(::UInt8) = nothing

# The first evaluation will not be profiled.
sextets2octets(chars1_decoded_stateful2octets, discard)

Profile.Allocs.@profile sample_rate=1.0 sextets2octets(chars1_decoded_stateful2octets, discard)
pr = Profile.Allocs.fetch()
open("profile1.txt", "w") do s
    Profile.print(IOContext(s, :displaysize => (24, 500)), pr, format=:flat)
end


#=
The file profile1.txt shows that both indicated lines of function pack() give rise to heap allocation.
=#

