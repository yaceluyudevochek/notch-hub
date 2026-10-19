# Загружает libNowPlaying.dylib в системный perl, которому MediaRemote доверяет.
# Использование: perl NowPlaying.pl <путь к dylib> stream|send
use strict;
use DynaLoader;

my ($lib, $mode) = @ARGV;
my $handle = DynaLoader::dl_load_file($lib, 0) or die "load failed: " . DynaLoader::dl_error();
my $symbol = DynaLoader::dl_find_symbol($handle, $mode eq 'send' ? 'nh_send' : 'nh_stream')
    or die "symbol not found";
DynaLoader::dl_install_xsub('main::run', $symbol);
run();
