#
#===============================================================================
#
#         FILE: debug.t
#
#  DESCRIPTION: 
#
#        FILES: ---
#         BUGS: ---
#        NOTES: ---
#       AUTHOR: YOUR NAME (), 
# ORGANIZATION: 
#      VERSION: 1.0
#      CREATED: 13.02.2016 22:45:56
#     REVISION: ---
#===============================================================================

use strict;
use warnings;
use feature ':5.20';

use Test::More;                      # last test to print
use Dancer ':script';

BEGIN { use_ok('Dancer::Plugin::Common'); }
require_ok('Dancer::Plugin::Common');

say transliterate("В чащах юга жил был цитрус. Да, но фальшивый экземпляр.");

done_testing;
