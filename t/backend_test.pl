#!/usr/bin/env perl
###################################################
#
#  Test script for Shutter screenshot backend detection
#  Run this script to verify Wayland/X11 detection and capabilities
#
#  Usage: perl t/backend_test.pl
#
###################################################

use utf8;
use strict;
use warnings;
use FindBin '$Bin';
use Test::More;

# Add the modules path
use lib "$Bin/../share/shutter/resources/modules";

# Test Backend module
use_ok('Shutter::Screenshot::Backend');

# Create backend instance
my $backend = Shutter::Screenshot::Backend->new();
ok($backend, "Backend instance created");

# Test session type detection
my $session_type = $backend->get_session_type();
ok($session_type, "Session type detected: $session_type");
ok($session_type eq 'x11' || $session_type eq 'wayland', "Session type is valid");

# Test boolean methods
my $is_wayland = $backend->is_wayland();
my $is_x11 = $backend->is_x11();
ok(defined $is_wayland, "is_wayland returns defined value");
ok(defined $is_x11, "is_x11 returns defined value");
ok($is_wayland xor $is_x11, "Session is either X11 or Wayland, not both");

# Test capabilities
my $caps = $backend->get_capabilities();
ok($caps, "Capabilities hash returned");
ok(ref($caps) eq 'HASH', "Capabilities is a hashref");

# Report detected capabilities
diag("Detected capabilities:");
for my $cap (sort keys %$caps) {
    diag("  $cap: $caps->{$cap}");
}

# Test can_capture method
ok(defined $backend->can_capture('full_screen'), "can_capture works for full_screen");
ok(defined $backend->can_capture('selection'), "can_capture works for selection");
ok(defined $backend->can_capture('window'), "can_capture works for window");

# On X11, all features should be available
if ($is_x11) {
    ok($backend->can_capture('full_screen'), "X11: full_screen available");
    ok($backend->can_capture('selection'), "X11: selection available");
    ok($backend->can_capture('window'), "X11: window available");
    ok($backend->can_capture('menu'), "X11: menu available");
    ok($backend->can_capture('tooltip'), "X11: tooltip available");
}

# Test backend selection
my $method = $backend->get_backend_for_mode('full_screen');
ok($method, "Backend method returned for full_screen: $method");

if ($is_wayland) {
    diag("Running on Wayland - testing Wayland-specific features");

    # Test unavailable reason messages
    my $reason = $backend->get_unavailable_reason('menu');
    ok($reason, "Unavailable reason for menu: $reason");

    $reason = $backend->get_unavailable_reason('tooltip');
    ok($reason, "Unavailable reason for tooltip: $reason");

    # Test XDG portal detection
    my $has_portal = $backend->has_xdg_portal();
    diag("XDG Portal available: " . ($has_portal ? "yes" : "no"));

    # Test gnome-screenshot detection
    my $has_gnome = $backend->has_gnome_screenshot();
    diag("gnome-screenshot available: " . ($has_gnome ? "yes" : "no"));

    # Test grim detection
    my $has_grim = $backend->has_grim();
    diag("grim+slurp available: " . ($has_grim ? "yes" : "no"));
}

# Test singleton pattern
my $backend2 = Shutter::Screenshot::Backend->instance();
ok($backend2, "Singleton instance returned");
is($backend, $backend2, "Singleton returns same instance");

done_testing();

print "\n";
print "=" x 60 . "\n";
print "BACKEND TEST SUMMARY\n";
print "=" x 60 . "\n";
print "Session type: $session_type\n";
print "X11 supported: " . ($is_x11 ? "yes" : "no") . "\n";
print "Wayland: " . ($is_wayland ? "yes" : "no") . "\n";
print "\n";
print "Available capture modes:\n";
for my $mode (qw(full_screen selection window active_window menu tooltip)) {
    my $available = $backend->can_capture($mode);
    printf "  %-15s %s\n", $mode . ":", ($available ? "yes" : "no");
}
print "=" x 60 . "\n";
