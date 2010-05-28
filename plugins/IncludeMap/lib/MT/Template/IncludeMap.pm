package MT::Template::IncludeMap;
use strict;
use warnings;
use MT;
use base qw( MT::Object );

__PACKAGE__->install_properties({
    column_defs => {
        'id'               => 'integer not null auto_increment',
        'template_id'      => 'integer',
        'template_name'    => 'string(255)',
        'template_blog_id' => 'integer',
        'module_id'        => 'integer',
        'module_name'      => 'string(255)',
        'module_blog_id'   => 'integer',

    },
    datasource  => 'include_map',
    primary_key => 'id',
});

sub class_label {
    MT->translate("Include Map");
}

sub make_map {
    my $pkg = shift;
    my ( $tmpl ) = @_;
    require MT::Builder;
    require MT::Template::Context;

    my $build = MT::Builder->new;
    my $token = $build->compile( MT::Template::Context->new, $tmpl->text );
    my @incs;
    push @incs, @{ MT::Template::Tokens::getElementsByTagName($token, 'include')      || []};
    push @incs, @{ MT::Template::Tokens::getElementsByTagName($token, 'includeBlock') || []};
    push @incs, @{ MT::Template::Tokens::getElementsByTagName($token, 'widgetSet')    || []};
    push @incs, @{ MT::Template::Tokens::getElementsByTagName($token, 'widgetManager')|| []};

    my $tmpl_blog_id = $tmpl->blog_id;
    my $map_class = MT->model('include_map');
    $map_class->remove({ template_id => $tmpl->id });
    for my $inc ( @incs ) {
        my $arg = $inc->[1]
            or next;

        my $name = $arg->{module}
                || $arg->{widget}
#                || $arg->{identifier}
#                || $arg->{file}
                || $arg->{name}
            or next;
        my $blog_id
            = $arg->{global}             ? 0
            : defined( $arg->{blog_id} ) ? $arg->{blog_id}
            :                              undef
            ;
        next if defined $blog_id && $blog_id !~ /^\d+$/;
        my $mod = MT->model('template')->load(
            { name => $name,
              blog_id => ( defined $blog_id ? $blog_id : [ 0, $tmpl_blog_id ] ) },
            { sort => 'blog_id',
              direction => 'descend',
        });
        my $map = $map_class->new;
        $map->set_values({
            template_id      => $tmpl->id,
            template_name    => $tmpl->name,
            template_blog_id => $tmpl->blog_id,
            module_id        => $mod ? $mod->id      : 0,
            module_name      => $mod ? $mod->name    : 0,
            module_blog_id   => $mod ? $mod->blog_id : 0,
        });
        $map->save or die $map->errstr;
    }
    return 1;
}

sub remove_template {
    my $pkg = shift;
    my ( $mod ) = @_;
    $mod = $mod->id if ref $mod;
    MT->model('include_map')->remove({ temlate_id => $mod->id });
    my @maps = MT->model('include_map')->load({
        module_id => $mod,
    });
    my @removes;
    my @search_globals;
    while ( my $map = shift @maps ) {
        if ( $map->module_blog_id == 0 ) {
            push @removes, $map->id;
        }
        else {
            push @search_globals, $map;
        }
    }
    my @global_names = map { $_->module_name } @search_globals;
    my @global_tmpls = MT->model('template')->load({
        blog_id => 0,
        type    => { not => 'backup' },
        name    => \@global_names,
    });
    my %global_tmpls = map { $_->name => $_ } @global_tmpls;
    while ( my $map = shift @search_globals ) {
        if ( my $global = $global_tmpls{$map->module_name} ) {
            $map->module_id( $global->id );
            $map->module_name( $global->name );
            $map->blog_id( 0 );
            $map->save;
       }
        else {
            push @removes, $map->id;
        }
    }
    MT->model('include_map')->remove({ id => \@removes });
}

1;
