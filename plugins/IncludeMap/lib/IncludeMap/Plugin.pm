package IncludeMap::Plugin;
use strict;
use warnings;

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

1;
