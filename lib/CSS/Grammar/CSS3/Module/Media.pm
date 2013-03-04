use v6;

# CSS3 Media Module Extensions
# - specification: http://www.w3.org/TR/2012/REC-css3-mediaqueries-20120619/
#
# The CSS3 Core includes some basic CSS2.1 compatible @media at rules. This
# module follows the latest W3C recommendations, to extend the syntax.
#
# -- if you want the capability to to embed '@page' rules, you'll also need
#    to load the Paged Media extension module in your class structure.

grammar CSS::Grammar::CSS3::Module::Media:ver<20120619.000> {

    rule at_rule:sym<media> { \@(:i'media') <media_list> <media_rules> }

    rule media_rules {
        '{' [<?before [:i'@page']><at_rule>|<ruleset>]* <end_block>
    }

    rule media_list {<media_query> [',' <media_query>]*}
    rule media_query {[<media_op>? <media>|<media_expr>]
                      [:i'and' <media_expr>]*}
    rule media_op    {[:i'only'|'not']}
    rule media_expr  {'(' <media_feature> [ ':' [<expr=.resolution>|<expr>] ]? [')' | <unclosed_paren>]}
    rule media_feature {<ident>}

    token resolution {<num>(:i[dpi|dpcm])}
}

class CSS::Grammar::CSS3::Module::Media::Actions {

    # media_rules, media_list, media_type see core actions
    method media_query($/)   { make $.list($/) }
    method media_op($/)      { make $/.Str.lc }
    method media_expr($/)    { make $.node($/) }
    method resolution($/)    { make $._qty($/); }
    method media_feature($/) { make $<ident>.ast }
}