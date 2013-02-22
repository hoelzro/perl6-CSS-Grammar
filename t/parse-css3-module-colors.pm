#!/usr/bin/env perl6

use Test;

use CSS::Grammar;
use CSS::Grammar::CSS3;
use CSS::Grammar::Actions;
use CSS::Grammar::CSS3::Module::Colors;

# prepare our own composite class with font extensions

grammar t::CSS3::ColorGrammar
      is CSS::Grammar::CSS3
      is CSS::Grammar::CSS3::Module::Colors {};

class t::CSS3::ColorActions
    is CSS::Grammar::Actions
    is CSS::Grammar::CSS3::Module::Colors::Actions {};

use lib '.';
use t::CSS;

my $css_actions = t::CSS3::ColorActions.new;

for (
    term   => {input => 'rgb(70%, 50%, 10%, 0.5)',
               ast => {color_rgb => {r => 70, g => 50, b => 10, a=> .5}},
    },
    term   => {input => 'rgba(100%, 50%, 0%, 0.1)',
               ast => {color_rgba => {r => 100, g => 50, b => 0, a=> .1}},
    },
    term   => {input => 'hsl(120, 100%, 50%)',
               ast => {color_hsl => {h => 120, 's' => 100, 'l' => 50}},
    },
    term   => {input => 'hsla(240, 100%, 50%, 0.5)',
               ast => {color_hsla => {h => 240, 's' => 100, 'l' => 50, 'a' => .5}},
    },
    ) {
    my $rule = $_.key;
    my %test = $_.value;
    my $input = %test<input>;

    $css_actions.warnings = ();
    my $p3 = t::CSS3::ColorGrammar.parse( $input, :rule($rule), :actions($css_actions));
    t::CSS::compat_tests($input, $p3, :rule($rule), :compat('css3-color-composite'),
                         :warnings($css_actions.warnings),
                         :expected(%test) );
}

done;
