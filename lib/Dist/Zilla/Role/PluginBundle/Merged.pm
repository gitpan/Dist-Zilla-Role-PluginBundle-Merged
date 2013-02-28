package Dist::Zilla::Role::PluginBundle::Merged;

our $VERSION = '0.92'; # VERSION
# ABSTRACT: Mindnumbingly easy way to create a PluginBundle

use sanity;
use MooseX::Role::Parameterized;

use Class::Load;
use Storable 'dclone';

use String::RewritePrefix 0.005 rewrite => {
   -as => '_section_class',
   prefixes => {
      ''  => 'Dist::Zilla::Plugin::',
      '@' => 'Dist::Zilla::PluginBundle::',
      '=' => ''
   },
};

with 'Dist::Zilla::Role::PluginBundle::Easy';

parameter mv_plugins => (
   isa      => 'ArrayRef[Str]',
   required => 0,
   default  => sub { [] },
);

role {
   my $p = shift;

   method mvp_multivalue_args => sub {
      my @list = @{ $p->mv_plugins };
      return unless @list;

      my %multi;
      foreach my $name (@list) {
         my $class = _section_class($name);
         Class::Load::load_class($class);
         @multi{$class->mvp_multivalue_args} = () if $class->can('mvp_multivalue_args');
      }

      return keys %multi;
   };

   method add_merged => sub {
      my $self = shift;
      my @list = @_;
      my $arg = $self->payload;

      my @config;
      foreach my $name (@list) {
         if (ref $name) {
            $arg = $name;
            next;
         }

         my $class = _section_class($name);
         Class::Load::load_class($class);

         # handle mvp_aliases
         my %aliases = ();
         %aliases = %{$class->mvp_aliases} if $class->can('mvp_aliases');

         if ($name =~ /^\@/) {
            # just give it everything, since we can't separate them out
            $self->add_bundle($name => $arg);
         }
         else {
            my %payload;
            foreach my $k (keys %$arg) {
               $payload{$k} = $arg->{$k} if $class->can( $aliases{$k} || $k );
            }
            $self->add_plugins([ "=$class" => $name => \%payload ]);
         }
      }
   };

   method config_rename => sub {
      my $self     = shift;
      my $payload  = $self->payload;
      my $args     = dclone($payload);
      my $chg_list = ref $_[0] ? $_[0] : { @_ };

      foreach my $key (keys %$chg_list) {
         my $new_key = $chg_list->{$key};
         my $val     = delete $args->{$key};
         next unless ($new_key);
         $args->{$new_key} = $val if (defined $val);
      }

      return $args;
   };
};

42;



=pod

=encoding utf-8

=head1 NAME

Dist::Zilla::Role::PluginBundle::Merged - Mindnumbingly easy way to create a PluginBundle

=head1 SYNOPSIS

    # Yes, three lines of code works!
    package Dist::Zilla::PluginBundle::Foobar;
    Moose::with 'Dist::Zilla::Role::PluginBundle::Merged';
    sub configure { shift->add_merged( qw[ Plugin1 Plugin2 Plugin3 Plugin4 ] ); }
 
    # Or, as a more complex example...
    package Dist::Zilla::PluginBundle::Foobar;
    use Moose;
 
    with 'Dist::Zilla::Role::PluginBundle::Merged' => {
       mv_plugins => [ qw( Plugin1 =Dist::Zilla::Bizarro::Foobar Plugin2 ) ],
    };
 
    sub configure {
       my $self = shift;
       $self->add_merged(
          qw( Plugin1 @Bundle1 =Dist::Zilla::Bizarro::Foobar ),
          {},  # force no options on the following plugins
          qw( ArglessPlugin1 ArglessPlugin2 ),
          $self->config_rename(plugin_dupearg => 'dupearg', removearg => undef),
          qw( Plugin2 ),
       );
    }

=head1 DESCRIPTION

This is a PluginBundle role, based partially on the underlying code from L<Dist::Zilla::PluginBundle::Git>.
As you can see from the example above, it's incredibly easy to make a bundle from this role.  It uses
L<Dist::Zilla::Role::PluginBundle::Easy>, so you have access to those same methods.

=head1 METHODS

=head2 add_merged

The C<<< add_merged >>> method takes a list (not arrayref) of plugin names, bundle names (with the C<<< @ >>>
prefix), or full module names (with the C<<< = >>> prefix).  This method combines C<<< add_plugins >>> & C<<< add_bundle >>>,
and handles all of the payload merging for you.  For example, if your bundle is passed the following
options:

    [@Bundle]
    arg1 = blah
    arg2 = foobar

Then it will pass the C<<< arg1/arg2 >>> options to each of the plugins, B<IF> they support the option.
Specifically, it does a C<<< $class->can($arg) >>> check.  (Bundles are passed the entire payload set.)  If
C<<< arg1 >>> exists for multiple plugins, it will pass the same option to all of them.  If you need separate
options, you should consider using the C<<< config_rename >>> method.

It will also accept hashrefs anywhere in the list, which will replace the payload arguments while
it processes.  This is useful for changing the options "on-the-fly" as plugins get processed.  The
replacement is done in order, and the changes will persist until it reaches the end of the list, or
receives another replacement.

=head2 config_rename

This method is sort of like the L<config_slice|Dist::Zilla::Role::PluginBundle::Easy/config_slice> method,
but is more implicit than explicit.  It starts off with the entire payload (cloned), and renames any hash
pair that was passed:

    my $hash = $self->config_rename(foobar_arg1 => 'arg1');

This example will change the argument C<<< foobar_arg1 >>> to C<<< arg1 >>>.  This is handy if you want to make a
specific option for the plugin "Foobar" that doesn't clash with C<<< arg1 >>> on plugin "Baz":

    $self->add_merged(
       'Baz',
       $self->config_rename(foobar_arg1 => 'arg1', killme => ''),
       'Foobar',
    );

Any destination options are replaced.  Also, if the destination value is undef (or non-true), the key will
simply be deleted.  Keep in mind that this is all a clone of the payload, so extra calls to this method
will still start out with the original payload.

=head1 ROLE PARAMETERS

=head2 mv_plugins

Certain configuration parameters are "multi-value" ones (or MVPs), and L<Config::MVP> uses the
C<<< mvp_multivalue_args >>> sub in each class to identify which ones exist.  Since you are trying to merge the
configuration parameters of multiple plugins, you'll need to make sure your new plugin bundle identifies those
same MVPs.

Because the INI reader is closer to the beginning of the DZ plugin process, it would be too late for
C<<< add_merged >>> to start adding in keys to your C<<< mvp_multivalue_args >>> array.  Thus, this role is parameterized
with this single parameter, and comes with its own C<<< mvp_multivalue_args >>> method.  The syntax is a single
arrayref of strings in the same prefix structure as C<<< add_merged >>>.  For example:

    with 'Dist::Zilla::Role::PluginBundle::Merged' => {
       mv_plugins => [ qw( Plugin1 Plugin2 ) ],
    };

The above will identify these two plugins has having MVPs.  When L<Config::MVP> calls your C<<< mvp_multivalue_args >>>
sub (which is built into this role), it will load these two plugin classes and populate the contents
of B<their> C<<< mvp_multivalue_args >>> sub as a combined list to pass over to L<Config::MVP>.  In other words,
as long as you identify all of the plugins that would have multiple values, your stuff "just works".

If you need to identify any extra parameters as MVPs (like your own custom MVPs or "dupe preventing" parameters
that happen to be MVPs), you should consider combining C<<< mv_plugins >>> with an C<<< after mvp_multivalue_args >>> sub.

=head1 AVAILABILITY

The project homepage is L<https://github.com/SineSwiper/Dist-Zilla-Role-PluginBundle-Merged/wiki>.

The latest version of this module is available from the Comprehensive Perl
Archive Network (CPAN). Visit L<http://www.perl.com/CPAN/> to find a CPAN
site near you, or see L<https://metacpan.org/module/Dist::Zilla::Role::PluginBundle::Merged/>.

=for :stopwords cpan testmatrix url annocpan anno bugtracker rt cpants kwalitee diff irc mailto metadata placeholders metacpan

=head1 SUPPORT

=head2 Internet Relay Chat

You can get live help by using IRC ( Internet Relay Chat ). If you don't know what IRC is,
please read this excellent guide: L<http://en.wikipedia.org/wiki/Internet_Relay_Chat>. Please
be courteous and patient when talking to us, as we might be busy or sleeping! You can join
those networks/channels and get help:

=over 4

=item *

irc.perl.org

You can connect to the server at 'irc.perl.org' and join this channel: #distzilla then talk to this person for help: SineSwiper.

=back

=head2 Bugs / Feature Requests

Please report any bugs or feature requests via L<L<https://github.com/SineSwiper/Dist-Zilla-Role-PluginBundle-Merged/issues>|GitHub>.

=head1 AUTHOR

Brendan Byrd <BBYRD@CPAN.org>

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2013 by Brendan Byrd.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)

=cut


__END__
