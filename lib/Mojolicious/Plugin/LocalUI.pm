package Mojolicious::Plugin::LocalUI;

use Mojo::Base 'Mojolicious::Plugin';

use Browser::Open 'open_browser';
use File::ShareDir 'dist_file';
use Mojo::ByteStream 'b';
use Mojo::Util qw(hmac_sha1_sum steady_time);

sub register {
    my ($self, $app, $o) = @_;
    my %conf = (
	entry_path => '/',
	initial_wait => 10,
	final_wait => 3,
	api_prefix => '/hb/',
	%$o
       );
    my $api = Mojo::Path->new($conf{api_prefix})
      ->leading_slash(1)->trailing_slash(1);
    my ($init_path, $hb_path, $js_path)
      = map {$api->merge($_)->to_string} 
      qw(init hb heartbeat.js);

    $app->helper( 'localui.conf' => sub { \%conf });
    $app->hook(
	before_server_start => sub {
	    my ($server, $app) = @_;
	    return if $conf{browser_launched};
	    ++$conf{browser_launched};
	    return if (caller(7))[0] =~ m/Command::get$/;
	    my ($url) = 
	      map { 
		  $_->host($_->host =~ s![*]!localhost!r); 
	      }
	      grep {
		  $_->host =~ m/^(?:[*]|localhost|127[.]([0-9.]+))$/
	      }
	      map { Mojo::URL->new($_) }
	      @{$server->listen};
	    die "Must be listening at a loopback URI" unless $url;

	    $conf{seed} =
	      my $seed = _make_csrf($app, $$ . steady_time . rand . 'x');

	    $url->path($init_path)->query(s => $seed);
	    my $e = open_browser($url->to_string);
	    if ($e // 1) {
		unless ($e) {
		    die "Cannot find browser to execute";
		}
		else {
		    die "Error executing: ". Browser::Open::open_browser_cmd . "\n";
		}
	    }
	    _reset_timer($conf{initial_wait});
	});
    $app->routes->get(
	$init_path => sub {
	    my $c = shift;
	    my $seed = $c->param('s')//'' =~ s/[^0-9a-f]//gr;

	    my $u = Mojo::URL->new($conf{entry_path});
	    if (length($seed) >= 40
		  && $seed eq ($conf{seed}//'')) {
		delete $conf{seed};
		undef $c->session->{csrf_token}; # make sure we get a fresh one
		$conf{csrf} = my $csrf = $c->csrf_token;
		$u->query(csrf_token => $csrf);
	    }
	    $c->redirect_to($u);
	});
    $app->routes->get(
	$hb_path => sub {
	    my $c = shift;
	    state $hcount = 0;
	    if ($c->validation->csrf_protect->error('csrf_token')) {
print STDERR "bad csrf: ".$c->validation->input->{csrf_token}." vs ".$c->validation->csrf_token."\n";
		return $c->render(json => { error => 'unexpected origin' },
				  status => 400, message => 'Bad Request', info => 'unexpected origin');
	    }
	    _reset_timer($conf{final_wait});
	    $c->render(json => { h => ++$hcount });
	    #    return $c->helpers->reply->not_found()
	    #      if ($hcount > 5);
	});
    # $app->hook(
    # 	before_dispatch => sub {
    # 	    my $c = shift;
    # 	    return unless $conf{csrf};
    # 	    $c->reply->bad_request(info => 'unexpected origin')
    # 	      if $c->validation->csrf_protect->error('csrf_token');
    # 	});

    $app->static->extra->{$js_path =~ s!^/!!r} = 
      dist_file(__PACKAGE__ =~ s/::/-/gr, 'heartbeat.js');

    push @{$app->renderer->classes}, __PACKAGE__;
    
    $app->helper(
	'localui.jsload' => sub { 
	    my $cb = ref $_[-1] eq 'CODE' ? pop : undef;
	    my ($c, %option) = @_; 
	    my $csrf = $c->param('csrf_token')//'missing';
	    b(( join "", map { $c->javascript($_)."\n" }
		($option{nojquery} ? () : ('/mojo/jquery/jquery.js')),
		$js_path 
	       ) .
	       $c->javascript( sub { <<END 
\$.fn.heartbeat.defaults.ajax.url = '$hb_path';
\$.fn.heartbeat.defaults.ajax.headers['X-CSRF-Token'] = '$csrf';
END
 . $c->include('ready', format => 'js', nofinish => 0, %option, _cb => $cb);
}))
	});

    # $app->helper(
    # 	'reply.bad_request', sub {
    # 	    my $c = shift;
    # 	    my %options = (info => '', status => $c->stash('status') // 400,
    # 			   (@_%2 ? ('message') : (message => 'Bad Request')), @_);
    # 	    return $c->render(template => 'done', title => 'Error', %options);
    # });
}

sub _make_csrf {
    my ($app, $seed) = @_;
    hmac_sha1_sum(pack('h*',$seed), $app->secrets->[0]);
}

sub _reset_timer {
    state $hb_wait;
    state $timer;
    $hb_wait = shift if @_;
    Mojo::IOLoop->remove($timer)
	if defined $timer;
    $timer = Mojo::IOLoop->timer($hb_wait, sub { 
				     print STDERR "stopping...";
				     shift->stop;
				 });
}


1;

__DATA__

@@ layouts/done.html.ep
<!DOCTYPE html>
<html>
  <head><title><%= title %></title>
%= stylesheet begin
body { background-color: #ddd; font-family: helvetica; }
h1 { font-size: 40px; color: white }
% end
  </head>
  <body><%= content %></body>
</html>

@@ done.html.ep
% layout 'done';
% title $title;
<h1 id="header"><%= $header %></h1>
<h2><span id="status"></span> <span id="message"></span></h2>
<p id="info"></p>

@@ ready.js.ep
$.ready.then(function() {
    $().heartbeat()
%== $_cb ? $_cb->() : ''
% unless ($nofinish) {
    .on_finish(function(unexpected,o) {
% my ($hd,$bdy) = do {
%   my $d = Mojo::DOM->new($c->render_to_string(template => "done", format => "html", title => "Finished", header => "Close this window"));
%   map {"'" . (Mojo::Util::trim($d->at($_)->content)
%                =~ s/'/\\047/gr =~ s/\n/'\n    +'\\n/gr) . "'"} qw(head body)
% };
      $('head').html(<%== $hd %>);
      $('body').html(<%== $bdy %>);
      if (unexpected) {
        $('#header').html('Error');
        $('#status').html(o.code);
        $('#message').html(o.msg);
        $('#info').html(o.status == 'error' ? '' : "("+o.msg+")");
      }
    })
% }
    .start();
});


__END__

=encoding utf8

=head1 NAME

Mojolicious::Plugin::LocalUI - launch a dedicated local web browser UI window

=head1 SYNOPSIS

  # Mojolicious::Lite

  plugin 'LocalUI';

  get '/' => "index";
  #.. and whatever else

  app->start;
  __DATA__

  @@ index.html.ep
  % layout 'default';
  ...

  @@ layouts/default.html.ep
  <!DOCTYPE html>
  <html>
    <head> ...
  %= $c->localui->jsload;
    </head>
    <body><%= content %></body>
  </html>

=head1 DESCRIPTION

On server start, L<Mojolicious::Plugin::LocalUI> opens a dedicated window in your default internet browser.  This assumes an available desktop that L<Browser::Open> knows how to deal with.  The application must be listening on a loopback/localhost port (dies otherwise), and the server shuts down when the browser window (and descendants thereof) is subsequently closed.

This is a way to create low-effort desktop applications using L<Mojolicious> (cross-platform if your code is sufficiently portable).

=head1 OPTIONS

=head2 initial_wait

How many seconds to wait on server start for browser window to finish loading.  Defaults to 10.

=head2 final_wait

How many seconds to wait after browser window ceases communicating before terminating (we do not rely on C<window.unload>).  Defaults to 3.

Since javascript timer events from backgrounded/hidden tabs/windows are typically throttled, reducing this below 2 will most likely make the application terminate whenever the window is hidden or minimized.

=head2 entry_path

URI path for the entry point of your application (i.e., what to display when the brower window opens).  Defaults to C</>.

=head2 api_prefix

Path prefix for URIs used by this plugin.  This is where the various endpoints needed by this module live (and is also where the required javascript file(s) are served from).  Defaults to C</hb/>; it can be pretty much anything as long as it's distinct from what the rest of your application uses.  But it would be best to keep it short.

=head1 HELPERS

=head2 localui.jsload

Loads whatever javascript needs to be in the <head> section of every page to be displayed in the browser window.  You most likely want this in your default layout.

  %= $c->localui->jsload;

Or you can be more elaborate

  %= javascript 'https://code.jquery.com/jquery-3.3.1.min.js';
  %= $c->localui->jsload( nojquery => 1, begin
        .on_hb(function(h) {
          // do something on every heartbeat
	  $('#heartbeat').html(h);
        })
  % end );

Options include

=head3 nojquery

Suppress loading of jquery from the Mojolicious distribution, meaning you already loaded it from elsewhere (needs to be at least version 3.0).

=head3 nofinish

Suppress the default C<on_finish> handler.

=head3 begin

Final C<begin> block, if provided, will be assumed to be javascript code to further configure the heartbeat object (code is preceded by C<$().heartbeat()>), typically to add C<on_hb> or C<on_finish> handlers

=head1 METHODS

L<Mojolicious::Plugin::LocalUI> inherits all methods from
L<Mojolicious::Plugin> and implements the following new ones.

=head2 register

  $plugin->register(Mojolicious->new, entry_path => '/');

Register plugin in L<Mojolicious> application.

=head1 SEE ALSO

L<Mojolicious>, L<Mojolicious::Guides>, L<https://mojolicious.org>.

=cut
