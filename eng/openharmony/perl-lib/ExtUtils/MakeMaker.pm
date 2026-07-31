package ExtUtils::MakeMaker;

use strict;

sub import { }

package MM;

use strict;

sub maybe_command {
    my ($class, $path) = @_;
    return -f $path && -x $path ? $path : undef;
}

1;
