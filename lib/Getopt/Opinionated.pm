package Getopt::Opinionated;

use strict;
use warnings;

my %real_flags = map { $_ => 1 } qw/flag number many required/;
sub _real_flags {
    return %real_flags;
}

sub new {
    my ($class, $user_options) = @_;
    ref $user_options eq 'HASH' || die "new() accepts a hashref, not a list";

    my %aliases;

    my %resolved_options = map {
        my $original = $_;

        # We'll store the data we derive from the user's description of the
        # option in this
        my $option_body = {};

        # The name of the option, eg: "[v]erbose flag many"
        my ($name, @flags) = split(/ /, $original);

        # Remove the alias field, and lowercase it:
        # [F]ile -> file, saving 'F'
        if ( $name =~ s/\|\[(\w)\]$// || $name =~ s/\[(\w)\]/lc($1)/e ) {
            my $alias = $1;
            die "You've already set '$alias' as an $alias to " . $aliases{$alias}
                if exists $aliases{$alias};
            $aliases{$1} = $name;
        }
        $option_body->{'name'} = $name;

        # Set any flags
        my %allowed_flags = $class->_real_flags;
        for my $flag (@flags) {
            die "Unknown option: '$flag' in: $original"
                unless $allowed_flags{ $flag };
            $option_body->{$flag} = 1;
        }
        if ( $option_body->{'flag'} && $option_body->{'number'} ) {
            die "Can't turn '$name' in to both a flag and a number. " .
                "If you want people to specify the flag many times, use 'many'";
        } elsif ( $option_body->{'flag'} && $option_body->{'required'} ) {
            die "A required flag doesn't make sense for '$name'";
        }

        # Set the description
        $option_body->{'description'} = $user_options->{$original};

        $name => $option_body;

    } keys %$user_options;

    my $self = { options => \%resolved_options, aliases => \%aliases };
    bless $self, $class;
    return $self;
}

sub defaults {
    my ($self, $defaults) = @_;

    for my $key (keys %$defaults) {
        die "You specified a default for '$key', but we don't know about $key"
            unless exists $self->{'options'}->{$key};
        die "Setting a default for a flag makes no sense with '$key'"
            if $self->{'options'}->{$key}->{'flag'};
    }

    $self->{'defaults'} = $defaults;
    return $self;
}

sub catchall {
    my ( $self, $catchall ) = @_;
    $self->{'catchall'} = $catchall;
    return $self;
}

sub args_from {
    my ( $self, $args ) = @_;
    $self->{'args_from'} = $args;
    return $self;
}

sub parse {
    my ( $self, $subref ) = @_;
    my @args = @{ $self->{'args_from'} || \@ARGV};
    my @catchall;

    my %found;

    while ( @args ) {
        my $key = shift(@args);
        #warn "Key is $key";

        # If we encounter either a '--' or an argument with no hyphen, we're at
        # the end of the options list - stop processing and throw everything
        # else in the catchall
        if ( $key eq '--' ) {
            @catchall = @args;
            last;

        } elsif ( substr( $key, 0, 1 ) ne '-' ) {
            @catchall = ($key, @args);
            last;

        # Double '--' are probably the easiest. We make the choice to not deal
        # with --foo=bar style args.
        } elsif ( substr( $key, 0, 2) eq '--' ) {

            # Get the key without the prefix
            my $real_key = substr( $key, 2 );

            # Get what we know about dealing with this key
            my $options = $self->{'options'}->{$real_key};
            unless ( $options ) {
                if ( $real_key eq 'help' ) {
                    exit_usage();
                } else {
                    fail_usage("Unknown option --$real_key");
                }
            }

            # For flags, set it, and move on
            if ( $options->{'flag'} ) {
                if ( $options->{'many'} ) {
                    $found{ $real_key } = ($found{ $real_key } || 0) + 1;
                } else {
                    $found{ $real_key } = boolean(1);
                }

                next;
            }

            # Get the value...
            my $value = shift( @args ) || '';

            # Enforce numeric
            if ( $options->{'number'} ) {
                fail_usage("--$real_key must be a number")
                    unless $value =~ m/^[0-9\.]+$/;
            }

            # Either set or append the value
            if ( $options->{'many'} ) {
                $found{ $real_key } ||= [];
                push( @{ $found{ $real_key } }, $value );
            } else {
                if ( defined $found{ $real_key } ) {
                    fail_usage("You have defined $real_key twice");
                } else {
                    $found{ $real_key } = $value;
                }
            }

        # Single hyphen items. You can get some really weird cases here:
        #  tar -vvvzcfbla bla.tgz
        } else {
            my $alias = substr( $key, 1, 1 );
            my $real_key = $self->{'aliases'}->{ $alias } ||
                fail_usage("Unknown option -$alias");

            # Get what we know about dealing with this key
            my $options = $self->{'options'}->{$real_key};

            # Flags
            if ( $options->{'flag'} ) {
                # First of all, if it's a multiflag thingy, put the rest of the
                # options back on the stack
                if ( length $key > 2 ) {
                    unshift( @args, '-' . substr( $key, 2 ) );
                }

                if ( $options->{'many'} ) {
                    $found{ $real_key } = ($found{ $real_key } || 0) + 1;
                } else {
                    $found{ $real_key } = boolean(1);
                }

                next;
            }

            # Value might be in the key, or in the next value
            my $value;
            if ( length $key > 2 ) {
                $value = substr( $key, 2 );
            } else {
                $value = shift( @args ) || '';
            }

            # Enforce numeric
            if ( $options->{'number'} ) {
                fail_usage("-$alias must be a number")
                    unless $value =~ m/^[0-9\.]+$/;
            }

            # Either set or append the value
            if ( $options->{'many'} ) {
                $found{ $real_key } ||= [];
                push( @{ $found{ $real_key } }, $value );
            } else {
                if ( defined $found{ $real_key } ) {
                    fail_usage("You have defined $alias twice");
                } else {
                    $found{ $real_key } = $value;
                }
            }
        }
    }


    for my $option (keys %{ $self->{'options'} }) {
        # Check all required values were included
        if ( $self->{'options'}->{$option}->{'required'} ) {
            fail_usage("You must specify '$option'") unless
                defined $found{$option};
        # Flags should always be set, but false, if not true
        } elsif ( $self->{'options'}->{$option}->{'flag'} ) {
            $found{$option} ||= boolean(0);
        }

        # Set any defaults
        if (! defined $found{$option} && defined $self->{'defaults'}->{$option} ) {
            $found{$option} = $self->{'defaults'}->{$option};
        }
    }

    if ( @catchall ) {
        $found{ $self->{'catchall'} || 'catchall' } = \@catchall;
    }

    # Almost ready to rock and roll...
    if ( $subref ) {
        my $returned = $subref->{ \%found } ||
            die "Subref to parse() didn't return true value";
        unless (ref $returned) {
            fail_usage( $returned );
        } else {
            return $returned;
        }
    }

    return \%found;
}

sub boolean {
    my $for = shift;
    if ( $INC{'JSON/XS.pm'} ) {
        return $for ? JSON::XS::true : JSON::XS::false;
    } else {
        return $for;
    }
}

1;
