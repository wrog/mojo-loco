# NAME

Mojolicious::Plugin::Loco - launch local GUI via default web browser

# VERSION

version 0.001

# SYNOPSIS

```perl
# Mojolicious::Lite

plugin 'Loco';

get '/' => "index";
#...
app->start;

__DATA__

@@ index.html.ep
% layout 'default';
#...

@@ layouts/default.html.ep
<!DOCTYPE html>
<html><head>

%= $c->loco->jsload;

</head><body>
%= content
</body></html>
```

# DESCRIPTION

On server start, [Mojolicious::Plugin::Loco](https://metacpan.org/pod/Mojolicious::Plugin::Loco) opens a dedicated window in your default internet browser.  This assumes an available desktop that [Browser::Open](https://metacpan.org/pod/Browser::Open) knows how to deal with.  The application must be listening on a loopback/localhost port (dies otherwise), and the server shuts down when the browser window (and descendants thereof) is subsequently closed.

This is a way to create low-effort desktop applications using [Mojolicious](https://metacpan.org/pod/Mojolicious) (cross-platform if your code is sufficiently portable).

# OPTIONS

## initial\_wait

How many seconds to wait on server start for browser window to finish loading.  Defaults to 10.

## final\_wait

How many seconds to wait after browser window ceases communicating before terminating (we do not rely on `window.unload`).  Defaults to 3.

Since javascript timer events from backgrounded/hidden tabs/windows are typically throttled, reducing this below 2 will most likely make the application terminate whenever the window is hidden or minimized.

## entry\_path

URI path for the entry point of your application (i.e., what to display when the brower window opens).  Defaults to `/`.

## api\_prefix

Path prefix for URIs used by this plugin.  This is where the various endpoints needed by this module live (and is also where the required javascript file(s) are served from).  Defaults to `/hb/`; it can be pretty much anything as long as it's distinct from what the rest of your application uses.  But it would be best to keep it short.

# HELPERS

## loco.jsload

Loads whatever javascript needs to be in the &lt;head> section of every page to be displayed in the browser window.  You most likely want this in your default layout.

```
%= $c->loco->jsload;
```

Or you can be more elaborate

```perl
%= javascript 'https://code.jquery.com/jquery-3.3.1.min.js';
%= $c->loco->jsload( nojquery => 1, begin
      .on_hb(function(h) {
        // do something on every heartbeat
        $('#heartbeat').html(h);
      })
% end );
```

Options include

### nojquery

Suppress loading of jquery from the Mojolicious distribution, meaning you already loaded it from elsewhere (needs to be at least version 3.0).

### nofinish

Suppress the default `on_finish` handler.

### begin

Final `begin` block, if provided, will be assumed to be javascript code to further configure the heartbeat object (code is preceded by `$().heartbeat()`), typically to add `on_hb` or `on_finish` handlers

# METHODS

[Mojolicious::Plugin::Loco](https://metacpan.org/pod/Mojolicious::Plugin::Loco) inherits all methods from
[Mojolicious::Plugin](https://metacpan.org/pod/Mojolicious::Plugin) and implements the following new ones.

## register

```perl
$plugin->register(Mojolicious->new, entry_path => '/');
```

Register plugin in [Mojolicious](https://metacpan.org/pod/Mojolicious) application.

# SEE ALSO

[Mojolicious](https://metacpan.org/pod/Mojolicious), [Mojolicious::Guides](https://metacpan.org/pod/Mojolicious::Guides), [https://mojolicious.org](https://mojolicious.org).

# AUTHOR

Roger Crew <wrog@cpan.org>

# COPYRIGHT AND LICENSE

This software is copyright (c) 2018 by Roger Crew.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.
