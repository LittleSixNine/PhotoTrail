package IO::Uncompress::Brotli;
use strict;
use warnings;
use PhotoTrail::Brotli;
sub unbro { return PhotoTrail::Brotli::codec('decode', $_[0], $_[1]); }
1;
