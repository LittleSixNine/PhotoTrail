package IO::Compress::Brotli;
use strict;
use warnings;
use PhotoTrail::Brotli;
sub bro { return PhotoTrail::Brotli::codec('encode', $_[0]); }
1;
