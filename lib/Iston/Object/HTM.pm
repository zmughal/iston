package Iston::Object::HTM;
# Abstract: Hierarchical Triangular Map

use 5.12.0;

use Carp;
use Iston::Utils qw/generate_list_id/;
use Iston::Vector qw/normal/;
use List::MoreUtils qw/first_index/;
use List::Util qw/max min reduce/;
use Math::Trig;
use Moo;
use Function::Parameters qw(:strict);
use OpenGL qw(:all);

use aliased qw/Iston::Triangle/;
use aliased qw/Iston::TrianglePath/;
use aliased qw/Iston::Vector/;
use aliased qw/Iston::Vertex/;

# OK, let's calculate the defaults;
my $_R  = 1;

my $_vertices = [
    Vertex->new([0,  $_R, 0]), # top
    Vertex->new([0, -$_R, 0]), # bottom
    Vertex->new([$_R * sin(deg2rad 45) , 0, $_R * sin(deg2rad  45)]),  # front left
    Vertex->new([$_R * sin(deg2rad -45), 0, $_R * sin(deg2rad  45)]),  # front righ
    Vertex->new([$_R * sin(deg2rad -45), 0, $_R * sin(deg2rad -45)]),  # back right
    Vertex->new([$_R * sin(deg2rad 45) , 0, $_R * sin(deg2rad -45)]),  # back left
];

my $_indices = [
    0, 3, 2, # 0: north-front
    0, 4, 3, # 1: north-right
    0, 5, 4, # 2: north-back
    0, 2, 5, # 3: north-left
    1, 2, 3, # 4: south-front
    1, 3, 4, # 5: south-right
    1, 4, 5, # 6: south-back
    1, 5, 2, # 7: south-left
];

has level        => (is => 'rw', default => sub { 0  }, trigger => 1 );
has levels_cache => (is => 'ro', default => sub { {} } );
has triangles    => (is => 'rw', default =>
    sub {
        my @triangles =
            map {
                my @v_indices = ($_*3 .. $_*3+2);
                my @vertices =
                    map { $_vertices->[$_] }
                    map { $_indices->[$_] }
                    @v_indices;
                Triangle->new(
                    vertices    => \@vertices,
                    path        => TrianglePath->new($_),
                    tesselation => 1,
                );
            } (0 .. @$_indices/3 - 1);
        return \@triangles;
    } );

has draw_function => (is => 'lazy', clearer => 1);

with('Iston::Drawable');

method BUILD {
    $self->levels_cache->{$self->level} = $self->triangles;
    $self->_calculate_normals;
    $self->_prepare_data;
};


method _calculate_normals {
    my $triangles = $self->triangles;
    my %triangles_of;
    my %index_of_vertex;
    for my $t (@$triangles) {
        my $vertices = $t->vertices;
        for my $idx (0 .. @$vertices-1) {
            my $v = $vertices->[$idx];
            push @{$triangles_of{$v}}, $t;
            $index_of_vertex{$v}->{$t} = $idx;
        }
    }
    for my $v (keys %triangles_of) {
        my $avg =
            reduce { $a + $b }
            map { $_->normal }
            @{ $triangles_of{$v} };
        my $n = $avg->normalize;
        for my $t (@{ $triangles_of{$v} }) {
            my $v_idx = $index_of_vertex{$v}->{$t};
            $t->normals->[$v_idx] = $n;
        }
    }
};

method _build_texture_id {
    my $triangles = $self->triangles;
    my %shares_for;
    for my $t_idx (0 .. @$triangles-1) {
        my $t = $triangles->[$t_idx];
        if (exists $t->{payload}->{time_share}) {
            my $share = $t->{payload}->{time_share};
            push @{ $shares_for{$share} }, $t;
        }
    }
    if (!%shares_for) {
        my ($width, $height) = (4, 4);
        my $texture = OpenGL::Image->new(width=>$width,height=>$height);
        my ($texture_id) = glGenTextures_p(1);
        my $share = 1.0;
        # seems that, gl_format is GL_BGRA, and not  GL_RGBA
        for my $x ( 0 .. $width-1) {
            for my $y (0 .. $height-1) {
                $texture->SetPixel($x, $y, 0.0, $share, $share, 1.0);
            }
        }
        glBindTexture(GL_TEXTURE_2D, $texture_id);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        my($internal_format, $format, $type) = $texture->Get('gl_internalformat','gl_format','gl_type');
        glTexImage2D_c(GL_TEXTURE_2D, 0, $internal_format, $width, $height,
                       0, $format, $type, $texture->Ptr());
        my @uv_mappings = map {
            ([0.0, 0.0], [0.0, 1.0], [1.0, 1.0]);
        } @$triangles;
        $self->uv_mappings(\@uv_mappings);
        return $texture_id;
    }
};

method _prepare_data {
    my $triangles = $self->triangles;
    my @vertices;
    my @normals;
    my @indices;
    for my $t_idx (0 .. @$triangles-1) {
        my $t = $triangles->[$t_idx];
        my $vertices = $t->vertices;
        my $normals = $t->normals;
        push @vertices, @$vertices;
        push @normals, @$normals;
        push @indices, map { $_ + ($t_idx*3) } (0, 1, 2);
    }
    $self->vertices(\@vertices);
    $self->normals(\@normals);
    $self->indices(\@indices);
    $self->clear_texture_id;
}

method _trigger_level($level) {
    my $current_triangles = $self->triangles;
    for my $l (0 .. $level) {
        $self->levels_cache->{$l} //= do {
            my @triangles = map {
                @{ $_->subtriangles() }
            } @$current_triangles;
            \@triangles;
        };
        $current_triangles = $self->levels_cache->{$l};
    }
    $self->triangles($current_triangles);
    $self->_calculate_normals;
    $self->_prepare_data;
    $self->clear_draw_function;
}

method rotate($axis,$value = undef){
    if (defined $value) {
        for (@{ $self->triangles }) {
            $_->rotate($axis, $value);
        }
    }
    else {
        return $self->triangles->[0]->rotate($axis);
    }
}

method radius {
    return 1;
};

1;
