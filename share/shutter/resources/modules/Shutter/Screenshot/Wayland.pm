###################################################
#
#  Copyright (C) 2020-2021 Google LLC, contributed by Alexey Sokolov <sokolov@google.com>
#  Copyright (C) 2024 Shutter Contributors
#
#  This file is part of Shutter.
#
#  Shutter is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 3 of the License, or
#  (at your option) any later version.
#
#  Shutter is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with Shutter; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
#
###################################################

use utf8;
use strict;
use warnings;

package Shutter::Screenshot::Wayland;

use File::Temp qw/ tempfile /;
use File::Which;
use Net::DBus;
use Net::DBus::Reactor;

# XDG Desktop Portal screenshot
# This is the primary method for Wayland screenshot capture
# Supports both full screen and interactive selection (portal version 2+)
sub xdg_portal {
    my $screenshooter = shift;
    my $options = shift // {};

    my $reactor = Net::DBus::Reactor->main;
    my $bus = Net::DBus->find;
    my $me = $bus->get_unique_name;
    $me =~ s/\./_/g;
    $me =~ s/^://g;

    my $pixbuf;

    eval {
        my $portal_service = $bus->get_service('org.freedesktop.portal.Desktop');
        my $portal = $portal_service->get_object('/org/freedesktop/portal/desktop',
            'org.freedesktop.portal.Screenshot');

        my $num;
        my $output;
        my $cb = sub {
            ($num, $output) = @_;
            $reactor->shutdown;
        };

        my $token = 'shutter' . int(rand(1000000));
        $token =~ s/\.//g;

        my $request = $portal_service->get_object(
            "/org/freedesktop/portal/desktop/request/$me/$token",
            'org.freedesktop.portal.Request');
        my $conn = $request->connect_to_signal(Response => $cb);

        # Build portal options
        my %portal_opts = (handle_token => $token);

        # Interactive mode - let the portal handle selection UI
        if ($options->{interactive}) {
            $portal_opts{interactive} = Net::DBus::dbus_boolean(1);
        }

        my $request_path = $portal->Screenshot('', \%portal_opts);

        if ($request->get_object_path ne $request_path) {
            $request->disconnect_from_signal(Response => $conn);
            $request = $portal_service->get_object($request_path, 'org.freedesktop.portal.Request');
            $conn = $request->connect_to_signal(Response => $cb);
        }

        # Add a timeout to prevent hanging forever
        my $timeout_id;
        $timeout_id = Glib::Timeout->add(60000, sub {
            print "XDG portal: timeout waiting for response\n";
            $reactor->shutdown;
            return 0;
        });

        $reactor->run;

        if ($timeout_id) {
            eval { Glib::Source->remove($timeout_id); };
        }

        $request->disconnect_from_signal(Response => $conn);

        if (!defined $num) {
            $screenshooter->{_error_text} = "No response from XDG portal (timeout or cancelled)";
            return 9;
        }

        if ($num != 0) {
            if ($num == 1) {
                $screenshooter->{_error_text} = "Screenshot cancelled by user";
            } else {
                $screenshooter->{_error_text} = "Response $num from XDG portal";
            }
            return 9;
        }

        if (!$output || !$output->{uri}) {
            $screenshooter->{_error_text} = "XDG portal returned no URI";
            return 9;
        }

        my $giofile = Glib::IO::File::new_for_uri($output->{uri});
        print "XDG portal: got file " . $giofile->get_path . "\n";

        $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($giofile->get_path);

        # Clean up temp file
        eval { $giofile->delete; };
    };

    if ($@) {
        $screenshooter->{_error_text} = $@;
        print "XDG portal error: $@\n";
        return 9;
    }

    return $pixbuf;
}

# XDG Portal with interactive selection
sub xdg_portal_selection {
    my $screenshooter = shift;
    return xdg_portal($screenshooter, { interactive => 1 });
}

# Capture using gnome-screenshot command line tool
# This works on both X11 and Wayland in GNOME environments
sub gnome_screenshot {
    my $screenshooter = shift;
    my $mode = shift // 'full';  # 'full', 'selection', 'window'
    my $options = shift // {};

    unless (defined which('gnome-screenshot')) {
        $screenshooter->{_error_text} = "gnome-screenshot is not installed";
        return 9;
    }

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.png', UNLINK => 1);
    close($fh);

    my @cmd = ('gnome-screenshot', '-f', $tmpfile);

    if ($mode eq 'selection') {
        push @cmd, '-a';  # area/selection mode
    } elsif ($mode eq 'window') {
        push @cmd, '-w';  # window mode
    }
    # 'full' is default, no extra flag needed

    if ($options->{include_cursor}) {
        push @cmd, '-p';  # include pointer
    }

    if ($options->{delay} && $options->{delay} > 0) {
        push @cmd, '-d', int($options->{delay});
    }

    print "Wayland: Running: " . join(' ', @cmd) . "\n";

    my $result = system(@cmd);

    if ($result != 0) {
        if ($result == -1) {
            $screenshooter->{_error_text} = "Failed to execute gnome-screenshot: $!";
        } elsif ($result & 127) {
            $screenshooter->{_error_text} = "gnome-screenshot killed by signal " . ($result & 127);
        } else {
            my $exit_code = $result >> 8;
            if ($exit_code == 1) {
                $screenshooter->{_error_text} = "Screenshot cancelled by user";
            } else {
                $screenshooter->{_error_text} = "gnome-screenshot exited with code $exit_code";
            }
        }
        return 9;
    }

    unless (-f $tmpfile && -s $tmpfile) {
        $screenshooter->{_error_text} = "gnome-screenshot produced no output file";
        return 9;
    }

    my $pixbuf;
    eval {
        $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($tmpfile);
    };

    if ($@) {
        $screenshooter->{_error_text} = "Failed to load screenshot: $@";
        return 9;
    }

    # Clean up
    unlink($tmpfile);

    return $pixbuf;
}

# Capture full screen using gnome-screenshot
sub gnome_screenshot_full {
    my $screenshooter = shift;
    my $options = shift // {};
    return gnome_screenshot($screenshooter, 'full', $options);
}

# Capture selection using gnome-screenshot
sub gnome_screenshot_selection {
    my $screenshooter = shift;
    my $options = shift // {};
    return gnome_screenshot($screenshooter, 'selection', $options);
}

# Capture window using gnome-screenshot
sub gnome_screenshot_window {
    my $screenshooter = shift;
    my $options = shift // {};
    return gnome_screenshot($screenshooter, 'window', $options);
}

# Capture using grim (for wlroots-based compositors like Sway)
sub grim {
    my $screenshooter = shift;
    my $geometry = shift;  # Optional: "x,y widthxheight" for region
    my $options = shift // {};

    unless (defined which('grim')) {
        $screenshooter->{_error_text} = "grim is not installed";
        return 9;
    }

    my ($fh, $tmpfile) = tempfile(SUFFIX => '.png', UNLINK => 1);
    close($fh);

    my @cmd = ('grim');

    if ($options->{include_cursor}) {
        push @cmd, '-c';  # include cursor
    }

    if ($geometry) {
        push @cmd, '-g', $geometry;
    }

    push @cmd, $tmpfile;

    print "Wayland: Running: " . join(' ', @cmd) . "\n";

    my $result = system(@cmd);

    if ($result != 0) {
        $screenshooter->{_error_text} = "grim failed with exit code " . ($result >> 8);
        return 9;
    }

    unless (-f $tmpfile && -s $tmpfile) {
        $screenshooter->{_error_text} = "grim produced no output file";
        return 9;
    }

    my $pixbuf;
    eval {
        $pixbuf = Gtk3::Gdk::Pixbuf->new_from_file($tmpfile);
    };

    if ($@) {
        $screenshooter->{_error_text} = "Failed to load screenshot: $@";
        return 9;
    }

    unlink($tmpfile);

    return $pixbuf;
}

# Capture selection using grim + slurp
sub grim_selection {
    my $screenshooter = shift;
    my $options = shift // {};

    unless (defined which('grim') && defined which('slurp')) {
        $screenshooter->{_error_text} = "grim and slurp must both be installed for selection capture";
        return 9;
    }

    # First, get the selection geometry using slurp
    my $geometry = `slurp 2>/dev/null`;
    chomp($geometry);

    if ($? != 0 || !$geometry) {
        $screenshooter->{_error_text} = "Selection cancelled or slurp failed";
        return 9;
    }

    print "Wayland: slurp returned geometry: $geometry\n";

    return grim($screenshooter, $geometry, $options);
}

# High-level capture function that automatically selects the best method
sub capture {
    my $screenshooter = shift;
    my $mode = shift // 'full';  # 'full', 'selection', 'window'
    my $options = shift // {};

    require Shutter::Screenshot::Backend;
    my $backend = Shutter::Screenshot::Backend->instance();

    my $method = $backend->get_backend_for_mode($mode);

    unless ($method) {
        $screenshooter->{_error_text} = "No capture method available for mode '$mode' on Wayland";
        return 9;
    }

    print "Wayland: Using backend '$method' for mode '$mode'\n";

    if ($method eq 'xdg_portal') {
        if ($mode eq 'selection' || $mode eq 'select') {
            return xdg_portal_selection($screenshooter);
        }
        return xdg_portal($screenshooter);
    }
    elsif ($method eq 'gnome_screenshot') {
        my $gs_mode = $mode;
        $gs_mode = 'selection' if $mode eq 'select';
        $gs_mode = 'window' if $mode eq 'awindow';
        return gnome_screenshot($screenshooter, $gs_mode, $options);
    }
    elsif ($method eq 'grim') {
        return grim($screenshooter, undef, $options);
    }
    elsif ($method eq 'grim_slurp') {
        return grim_selection($screenshooter, $options);
    }

    $screenshooter->{_error_text} = "Unknown backend method: $method";
    return 9;
}

1;
