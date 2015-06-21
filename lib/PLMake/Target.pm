package PLMake::Target;
use Time::HiRes qw( stat );

use strict;

sub new {
    my $class = shift;
    my ( $name, $flags ) = @_;
    my $self = bless {
        name => $name,
        flags => $flags,
        rules => {},
    }, $class;

    my @stat = stat($name);
    if (@stat) {
        $self->{timestamp} = $stat[9];
    }
    else {
        $self->{timestamp} = 0;
        $self->{flags}->{missing} = 1;
    }

    return $self;
}

sub set_flags {
    my $self = shift;
    %{$self->{flags}} = (%{$self->{flags}}, @_);
}

sub has_rule {
    my ($self, $rule) = @_;

    return $self->{rules}->{$rule};
}

sub add_rule {
    my ($self, $rule) = @_;

    $self->{rules}->{$rule} = $rule;
}

sub remove_rule {
    my ($self, $rule) = @_;

    delete $self->{rules}->{$rule};
}

sub get_rules {
    my ($self) = @_;

    return values %{$self->{rules}};
}

sub rule {
    my ($self) = @_;

    my @rules = $self->get_rules;
    die "conflicting rules" if @rules > 1;
    return $rules[0];
}

sub must_remake {
    my ($self, $hash, $ts) = @_;
    my $ret = 0;

    if (defined $ts) {
        if ($ts <= $self->{timestamp}) {
            $ts = $self->{timestamp};
            $ret = 1;
        }
    }
    else {
        $ts = $self->{timestamp};
    }
    
    $ts = 0 if $self->{flags}->{remake};
    
    for my $s (@{$self->{sources}}) {
        if ($s->must_remake($hash, $ts)) {
            $self->{flags}->{remake} = 1;
            $hash->{$self} = $self;
        }
    }
    
    if ($self->{flags}->{phony} && $self->rule) {
        $self->{flags}->{remake} = 1;
        $hash->{$self} = $self;
    }
    
    $ret = 1 if $self->{flags}->{remake};
    
    die "can't remake $self->{name}" if $self->{flags}->{missing} && !$self->rule;
    
    return $ret;
}

1;

