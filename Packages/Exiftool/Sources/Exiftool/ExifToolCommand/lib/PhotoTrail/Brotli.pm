# PhotoTrail adapter for ExifTool's Brotli hooks using macOS Compression.
package PhotoTrail::Brotli;
use strict;
use warnings;
use File::Basename qw(dirname);
use File::Spec;
use File::Temp qw(tempdir);

sub codec {
    my ($mode, $data, $limit) = @_;
    $limit = 100000000 unless defined $limit;
    die "Invalid Brotli buffer limit" unless $limit =~ /^\d+$/ && $limit > 0 && $limit <= 100000000;
    die "Brotli input too large" if length($data) > 100000000;
    my $helper = File::Spec->catfile(dirname(dirname(dirname(dirname(__FILE__)))), 'MetadataBrotli.bin');
    die "Metadata Brotli codec unavailable" unless -x $helper;
    my $folder = tempdir('phototrail-brotli-XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
    my $input = File::Spec->catfile($folder, 'input');
    my $output = File::Spec->catfile($folder, 'output');
    open(my $file, '>:raw', $input) or die "Cannot create Brotli input";
    print {$file} $data or die "Cannot write Brotli input";
    close($file) or die "Cannot close Brotli input";
    system { $helper } $helper, $mode, $input, $output, $limit;
    die "Metadata Brotli codec failed" if $? != 0;
    open(my $result, '<:raw', $output) or die "Cannot read Brotli result";
    local $/;
    my $decoded = <$result>;
    close($result) or die "Cannot close Brotli result";
    die "Brotli result too large" if length($decoded) > $limit;
    return $decoded;
}
1;
