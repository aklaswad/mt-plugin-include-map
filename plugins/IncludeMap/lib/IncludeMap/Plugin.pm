package IncludeMap::Plugin;
use strict;
use warnings;
use JSON;
sub post_save {
    my ( $cb, $obj ) = @_;
    MT->model('include_map')->make_map( $obj );
    1;
}

sub post_remove {
    my ( $cb, $obj ) = @_;
    MT->model('include_map')->remove_template( $obj );
    1;
}

sub post_create_blog {
    my ( $cb, $blog ) = @_;
    my $blog_id = $blog->id;
    my @tmpls = MT->model('template')->load({ blog_id => $blog_id });
    for my $tmpl ( @tmpls ) {
        MT->model('include_map')->make_map($tmpl);
    }
}

sub cms_edit {
    my ( $cb, $app, $id, $obj, $param ) = @_;
    $app->{__edit_object} = $obj;
}

sub add_widget {
    my ( $cb, $app, $param, $tmpl ) = @_;
    my $obj = $app->{__edit_object};
    my @includings = MT->model('include_map')->load({
        module_id => $obj->id,
    });
    if ( scalar @includings ) {
        $param->{including_loop} = [ map {
            {
                including_name => $_->template_name,
                including_link => $app->mt_uri(
                    mode => 'view',
                    args => {
                        blog_id => $_->template_blog_id,
                        '_type' => 'template',
                        id => $_->template_id
                    }
                ),
            }} @includings ];
        $param->{have_includings} = 1;
    }

    my $include = <<'TMPL';
<mtapp:widget
    id="template-includings"
    label="<__trans phrase="Included by">">
    <ul>
        <mt:loop name="including_loop">
        <li><a href="<mt:var name="including_link">" class="icon-left icon-related"><mt:var name="including_name"></a></li>
        </mt:loop>
    </ul>
</mtapp:widget>
TMPL

    my $place_holder = $tmpl->getElementById('tag-list')
        or return;
    my $widget = $tmpl->createElement('if', { name => 'have_includings' });
    $widget->innerHTML($include);
    $tmpl->insertBefore($widget, $place_holder);
    1;
}

sub include_map {
    my $app = shift;
    $app->can_do('view_include_map')
        or return $app->return_to_dashboard(
            permission => 1,
        );
    my $blog_id = $app->param('blog_id')
        or return $app->error('Invalid Request');
    my %templates;
    my @templates = MT->model('template')->load({ type => { not => 'backup' }, blog_id => $blog_id });

    for my $template ( @templates ) {
        $templates{$template->id} = {
            id           => $template->id,
            tmpl_blog_id => $template->blog_id,
            name         => $template->name,
            other_blog   => 0,
            depth        => 0,
        }
    }

    my @maps = MT->model('include_map')->load([
        { template_blog_id => $blog_id },
        '-or' => { module_blog_id => $blog_id }
    ]);
    for my $map ( @maps ) {
        if ( !exists $templates{$map->template_id} ) {
            $templates{$map->template_id} = {
                id           => $map->template_id,
                tmpl_blog_id => $map->template_blog_id,
                name         => $map->template_name,
                other_blog   => ($map->template_blog_id != $blog_id),
                depth        => 0,
            }
        }
        if ( !exists $templates{$map->module_id} ) {
            $templates{$map->module_id} = {
                id           => $map->module_id,
                tmpl_blog_id => $map->module_blog_id,
                name         => $map->module_name,
                other_blog   => ($map->module_blog_id != $blog_id),
                depth        => 0,
            }
        }
    }
    my %include;
    my %include_by;

    for my $map ( @maps ) {
        $include{$map->template_id}  ||= [];
        $include_by{$map->module_id} ||= [];
        push @{ $include{$map->template_id} },  $map->module_id;
        push @{ $include_by{$map->module_id} }, $map->template_id;
    }
    for my $map ( @maps ) {
        $templates{$map->module_id}{included} = 1;
    }
    my @tops = grep { !$_->{included} } values %templates;
    my $depth_explorer;
    $depth_explorer = sub {
        my ( $tmpl, $depth ) = @_;
        if ( my $includes = $include{$tmpl->{id}} ) {
            for my $inc_id ( @$includes ) {
                my $inc = $templates{$inc_id};
                $inc->{depth} = $inc->{depth} > $depth ? $inc->{depth} : $depth;
                $depth_explorer->( $inc, $depth + 1 );
            }
        }
    };
    for my $top ( @tops ) {
        $depth_explorer->($top, 1);
    }
    my @depth;
    for my $tmpl ( values %templates ) {
        $depth[$tmpl->{depth}] ||= [];
        push @{ @depth[$tmpl->{depth}] }, $tmpl;
    }

    my %param;
    $param{maps} = \@maps;
    $param{templates} = \@depth;
    $param{include} = encode_json(\%include);
    $param{include_by} = encode_json(\%include_by);
    $app->load_tmpl( 'include_map.tmpl', \%param );
}

1;
