package Iston::Vertex;

use 5.12.0;

use Carp;

use overload
    'eq' => '_equal',
    '==' => '_equal',
    '""' => '_stringify',
    ;

sub new {
    my ($class, $values) = @_;
    croak "Vertex is defined exactly by 3 values"
        unless @$values == 3;

    my $copy = [@$values];
    bless $copy => $class;
};

sub _equal {
    my ($a, $b) = @_;
    my $r = 1;
    for (0 .. 2) {
        $r &= $a->[$_] == $b->[$_];
    }
    $r;
}

sub _stringify {
    my $self = shift;
    return sprintf('vertex[%0.4f, %0.4f, %0.4f]', @{$self}[0 .. 2]);
}

1;