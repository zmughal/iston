package Iston::Drawable;

use 5.12.0;

use Carp;
use Function::Parameters qw(:strict);
use Iston::Utils qw/identity as_oga/;
use Moo::Role;
use OpenGL qw(:all);

use aliased qw/Iston::Vector/;
use aliased qw/Iston::Vertex/;

# candidate for deletion
has rotation     => (is => 'rw', default => sub { [0, 0, 0] }, trigger => 1);
has enabled      => (is => 'rw', default => sub { 1 });
# candidate for deletion
has display_list => (is => 'ro', default => sub { 0 });

has center       => (is => 'lazy');
has boundaries   => (is => 'lazy');
has scale        => (is => 'rw', default => sub { 1; }, trigger => 1);
has vertices     => (is => 'rw', required => 0);
has indices      => (is => 'rw', required => 0);
has normals      => (is => 'rw', required => 0);
has uv_mappings  => (is => 'rw', required => 0);
has mode         => (is => 'rw', default => sub { 'normal' }, trigger => 1);

has texture_id    => (is => 'lazy', clearer => 1);
has draw_function => (is => 'lazy', clearer => 1);

has shader                => (is => 'rw', trigger => 1 );
has _uniform_my_texture   => (is => 'rw');
has _uniform_has_texture  => (is => 'rw');
has _uniform_has_lighting => (is => 'rw');
has _attribute_texcoord   => (is => 'rw');
has _attribute_coord3d    => (is => 'rw');
has _attribute_normal     => (is => 'rw');

has _text_coords_oga => (is => 'lazy');

# matrices
has model           => (is => 'rw', trigger => sub{ shift->clear_model_oga }, default => sub { identity; });
has model_translate => (is => 'rw', trigger => sub{ shift->clear_model_oga }, default => sub { identity; });
has model_scale     => (is => 'rw', trigger => sub{ shift->clear_model_oga }, default => sub { identity; });
has model_rotation  => (is => 'rw', trigger => sub{ shift->clear_model_oga }, default => sub { identity; });
has model_oga       => (is => 'lazy', clearer => 1);

# just cache
has _contexts => (is => 'rw', default => sub { {} });

method _trigger_shader($shader) {
    my ($mytexture, $has_texture, $has_lighting) = map {
        $shader->Map($_) // die("cannot map '$_' uniform");
    } qw/mytexture has_texture has_lighting/;
    my ($texcoord, $coord3d, $normal) = map {
        $shader->MapAttr($_) // die("cannot map attribute '$_'");
    } qw/texcoord coord3d N/;
    $self->_uniform_my_texture($mytexture);
    $self->_uniform_has_texture($has_texture);
    $self->_uniform_has_lighting($has_lighting);
    $self->_attribute_texcoord($texcoord);
    $self->_attribute_coord3d($coord3d);
    $self->_attribute_normal($normal);
}

method _trigger_rotation($values) {
    my $m = identity;
    for my $idx (0 .. @$values-1) {
        my $angle = $values->[$idx];
        if($angle) {
            my @axis_components = (0) x scalar(@$values);
            $axis_components[$idx] = 1;
            my $axis = Vector->new(\@axis_components);
            $m *= Iston::Utils::rotate($angle, $axis);
        }
    }
    $self->model_rotation($m);
}

method _trigger_scale($value) {
    $self->model_scale(Iston::Utils::scale($value));
}

sub _build_model_oga {
    my $self = shift;
    my $scale    = $self->model_scale;
    my $translate = $self->model_translate;
    my $rotation = $self->model_rotation;
    my $model = $self->model;
    my $matrix = $model * $rotation * $scale * $translate;
    $matrix = ~$matrix;
    return OpenGL::Array->new_list(GL_FLOAT, $matrix->as_list);
}

# candidate for deletion
sub rotate {
    my ($self, $axis, $value) = @_;
    if (defined $value) {
        $self->rotation->[$axis] = $value;
        $self->_trigger_rotation($self->rotation);
    }
    else {
        return $self->rotation->[$axis];
    }
}

method _trigger_mode {
    my $mode = $self->mode;
    if ($mode eq 'mesh') {
        $self->_contexts->{normal} = {
            indices => $self->indices,
        };
        $self->indices($self->_triangle_2_lines_indices);
    } else {
        $self->_contexts->{mesh} = {
            indices => $self->indices,
        };
        $self->indices($self->_contexts->{normal}->{indices});
    }
    $self->clear_draw_function;
};

method _triangle_2_lines_indices {
    my $source = $self->indices;
    my $components = 3;
    my @result = map {
        my $idx = $_;
        my @v = @{$source}[$idx*3 .. $idx*3+2];
        my @r = @v[0,1,1,2,2,0];
        @r;
    } (0 .. scalar(@$source) / $components-1);
    return \@result;
};

method _build_boundaries {
    my $first_vertex = $self->vertices->[0];
    my ($mins, $maxs) = map { Vertex->new($first_vertex) } (0 .. 1);
    my $vertices_count = scalar(@{$self->vertices});
    for my $vertex_index (0 .. $vertices_count-1) {
        my $v = $self->vertices->[$vertex_index];
        for my $c (0 .. 2) {
            $mins->[$c] = $v->[$c] if($mins->[$c] > $v->[$c]);
            $maxs->[$c] = $v->[$c] if($maxs->[$c] < $v->[$c]);
        }
    }
    return [$mins, $maxs];
};

method _build__text_coords_oga {
    my ($vbo_texcoords) = glGenBuffersARB_p(1);
    my $texcoords_oga = OpenGL::Array->new_list(
        GL_FLOAT, map { @$_ } @{ $self->uv_mappings }
    );
    $texcoords_oga->bind($vbo_texcoords);
    glBufferDataARB_p(GL_ARRAY_BUFFER_ARB, $texcoords_oga, GL_STATIC_DRAW_ARB);
    return $texcoords_oga;
}

method _build_draw_function {
    my $scale = $self->scale;

    my ($p_vertices, $p_normals) =
        map {
            my $v = $self->$_;
            croak "$_ is mandatory" if (!defined($v) or !@$v);
            $v;
        } qw/vertices normals/;
    my ($vertices, $normals) =
        map { as_oga($_) }
        ($p_vertices, $p_normals);
    my $components = 3; # number of coordinates
    my ($vbo_vertices, $vbo_normals) = glGenBuffersARB_p(2);

    $vertices->bind($vbo_vertices);
    glBufferDataARB_p(GL_ARRAY_BUFFER_ARB, $vertices, GL_STATIC_DRAW_ARB);

    $normals->bind($vbo_normals);
    glBufferDataARB_p(GL_ARRAY_BUFFER_ARB, $normals, GL_STATIC_DRAW_ARB);

    my $indices = $self->indices;
    my $indices_size = scalar(@$indices);
    my $mode = $self->mode;
    my $draw_mode = $mode eq 'normal'
        ? GL_TRIANGLES : GL_LINES;

    my $indices_oga =OpenGL::Array->new_list(
        GL_UNSIGNED_INT,
        @$indices
    );

    my $texture_id = $self->texture_id;
    $self->shader->Enable;

    my $has_texture_u = $self->_uniform_has_texture;
    glUniform1iARB($has_texture_u, defined($texture_id));
    my $has_lighting_u = $self->_uniform_has_lighting;
    glUniform1iARB($has_lighting_u, $ENV{ISTON_LIGHTING} // 1);

    $self->shader->Disable;

    my $draw_function = sub {
        $self->shader->Enable;

        $self->shader->SetMatrix(model => $self->model_oga);
        my $attribute_texcoord = $self->_attribute_texcoord;
        glEnableVertexAttribArrayARB($attribute_texcoord);

        if (defined $texture_id) {
            glActiveTextureARB(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, $texture_id);
            glUniform1iARB($self->_uniform_my_texture, 0); # /*GL_TEXTURE*/

            glBindBufferARB(GL_ARRAY_BUFFER, $self->_text_coords_oga->bound);
            glVertexAttribPointerARB_c($attribute_texcoord, 2, GL_FLOAT, 0, 0, 0);
        }

        my $attribute_coord3d = $self->_attribute_coord3d;
        glEnableVertexAttribArrayARB($attribute_coord3d);
        glBindBufferARB(GL_ARRAY_BUFFER, $vertices->bound);
        glVertexAttribPointerARB_c($attribute_coord3d, 3, GL_FLOAT, 0, 0, 0);

        my $attribute_normal = $self->_attribute_normal;
        glEnableVertexAttribArrayARB($attribute_normal);
        glBindBufferARB(GL_ARRAY_BUFFER, $normals->bound);
        glVertexAttribPointerARB_c($attribute_normal, 3, GL_FLOAT, 0, 0, 0);

        glDrawElements_c(GL_TRIANGLES, $indices_size, GL_UNSIGNED_INT, $indices_oga->ptr);

        glDisableVertexAttribArrayARB($attribute_coord3d);
        glDisableVertexAttribArrayARB($attribute_texcoord);
        $self->shader->Disable;
    };
    return $draw_function;
}

1;
