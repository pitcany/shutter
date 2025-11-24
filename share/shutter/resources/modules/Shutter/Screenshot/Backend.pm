###################################################
#
#  Copyright (C) 2008-2013 Mario Kemper <mario.kemper@gmail.com>
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

package Shutter::Screenshot::Backend;

use utf8;
use strict;
use warnings;

use File::Which;

# Singleton instance
my $_instance;

sub new {
    my $class = shift;

    # Return existing instance if available
    return $_instance if $_instance;

    my $self = {
        _session_type => undef,
        _capabilities => {},
        _detected => 0,
    };

    bless $self, $class;
    $_instance = $self;

    $self->_detect_session();
    $self->_detect_capabilities();

    return $self;
}

sub instance {
    my $class = shift;
    return $_instance || $class->new();
}

sub _detect_session {
    my $self = shift;

    # Check XDG_SESSION_TYPE environment variable
    my $session_type = $ENV{XDG_SESSION_TYPE} // '';

    # Also check WAYLAND_DISPLAY as a fallback
    if (!$session_type && $ENV{WAYLAND_DISPLAY}) {
        $session_type = 'wayland';
    }

    # Default to x11 if we can't detect
    $session_type ||= 'x11';

    $self->{_session_type} = lc($session_type);
    $self->{_detected} = 1;

    print "Backend: Detected session type: $self->{_session_type}\n";

    return $self->{_session_type};
}

sub _detect_capabilities {
    my $self = shift;

    my %caps = (
        full_screen => 0,
        selection => 0,
        window => 0,
        active_window => 0,
        menu => 0,
        tooltip => 0,
        include_cursor => 0,
        delay => 0,
        xdg_portal => 0,
        gnome_screenshot => 0,
        grim => 0,
        slurp => 0,
    );

    if ($self->is_wayland()) {
        # Check for XDG Desktop Portal
        $caps{xdg_portal} = $self->_check_xdg_portal();

        # Check for gnome-screenshot (works on both X11 and Wayland in GNOME)
        $caps{gnome_screenshot} = defined which('gnome-screenshot') ? 1 : 0;

        # Check for grim/slurp (wlroots-based compositors)
        $caps{grim} = defined which('grim') ? 1 : 0;
        $caps{slurp} = defined which('slurp') ? 1 : 0;

        # Determine available features based on tools
        if ($caps{xdg_portal}) {
            $caps{full_screen} = 1;
            # XDG portal Screenshot interface supports interactive selection since portal version 2
            $caps{selection} = 1;  # Portal handles selection UI
        }

        if ($caps{gnome_screenshot}) {
            $caps{full_screen} = 1;
            $caps{selection} = 1;  # gnome-screenshot -a for area selection
            $caps{window} = 1;     # gnome-screenshot -w for window
            $caps{include_cursor} = 1;
            $caps{delay} = 1;
        }

        if ($caps{grim} && $caps{slurp}) {
            $caps{full_screen} = 1;
            $caps{selection} = 1;
            $caps{include_cursor} = 1;
        }

    } else {
        # X11 - all features available via native methods
        $caps{full_screen} = 1;
        $caps{selection} = 1;
        $caps{window} = 1;
        $caps{active_window} = 1;
        $caps{menu} = 1;
        $caps{tooltip} = 1;
        $caps{include_cursor} = 1;
        $caps{delay} = 1;
    }

    $self->{_capabilities} = \%caps;

    print "Backend: Capabilities: " . join(", ",
        map { "$_=$caps{$_}" } sort keys %caps) . "\n";

    return \%caps;
}

sub _check_xdg_portal {
    my $self = shift;

    eval {
        require Net::DBus;
        my $bus = Net::DBus->find;
        my $portal_service = $bus->get_service('org.freedesktop.portal.Desktop');
        my $portal = $portal_service->get_object('/org/freedesktop/portal/desktop',
            'org.freedesktop.DBus.Properties');
        # Just checking if we can connect is enough
        return 1;
    };

    if ($@) {
        print "Backend: XDG Portal not available: $@\n";
        return 0;
    }

    return 1;
}

sub is_wayland {
    my $self = shift;
    return $self->{_session_type} eq 'wayland';
}

sub is_x11 {
    my $self = shift;
    return $self->{_session_type} eq 'x11';
}

sub get_session_type {
    my $self = shift;
    return $self->{_session_type};
}

sub get_capabilities {
    my $self = shift;
    return $self->{_capabilities};
}

sub can_capture {
    my ($self, $mode) = @_;
    return $self->{_capabilities}{$mode} // 0;
}

sub has_xdg_portal {
    my $self = shift;
    return $self->{_capabilities}{xdg_portal};
}

sub has_gnome_screenshot {
    my $self = shift;
    return $self->{_capabilities}{gnome_screenshot};
}

sub has_grim {
    my $self = shift;
    return $self->{_capabilities}{grim} && $self->{_capabilities}{slurp};
}

# Get the best available backend for a given capture mode
sub get_backend_for_mode {
    my ($self, $mode) = @_;

    if ($self->is_x11()) {
        return 'native';
    }

    # Wayland - determine best backend
    if ($mode eq 'full_screen' || $mode eq 'full') {
        if ($self->{_capabilities}{xdg_portal}) {
            return 'xdg_portal';
        }
        if ($self->{_capabilities}{gnome_screenshot}) {
            return 'gnome_screenshot';
        }
        if ($self->{_capabilities}{grim}) {
            return 'grim';
        }
    }
    elsif ($mode eq 'selection' || $mode eq 'select') {
        if ($self->{_capabilities}{gnome_screenshot}) {
            return 'gnome_screenshot';
        }
        if ($self->{_capabilities}{grim} && $self->{_capabilities}{slurp}) {
            return 'grim_slurp';
        }
        if ($self->{_capabilities}{xdg_portal}) {
            return 'xdg_portal';  # Portal may show its own selection UI
        }
    }
    elsif ($mode eq 'window' || $mode eq 'active_window' || $mode eq 'awindow') {
        if ($self->{_capabilities}{gnome_screenshot}) {
            return 'gnome_screenshot';
        }
    }

    return undef;
}

# Get user-friendly message about why a mode is unavailable
sub get_unavailable_reason {
    my ($self, $mode) = @_;

    if ($self->is_x11()) {
        return undef;  # Everything should work on X11
    }

    my $mode_names = {
        selection => "Selection",
        window => "Window",
        active_window => "Active window",
        menu => "Menu",
        tooltip => "Tooltip",
    };

    my $mode_name = $mode_names->{$mode} // $mode;

    if ($mode eq 'menu' || $mode eq 'tooltip') {
        return "$mode_name capture is not supported on Wayland due to security restrictions.";
    }

    if (!$self->can_capture($mode)) {
        if ($mode eq 'selection') {
            return "$mode_name capture requires gnome-screenshot or grim+slurp to be installed.";
        }
        if ($mode eq 'window' || $mode eq 'active_window') {
            return "$mode_name capture requires gnome-screenshot to be installed, or please use Xorg session.";
        }
        return "$mode_name capture is not available in Wayland session. Please switch to Xorg for this feature.";
    }

    return undef;
}

1;
