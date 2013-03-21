use v6;

# rules for constructing ASTs for CSS::Grammar

class CSS::Grammar::Actions {
    use CSS::Grammar::AST::Info;
    use CSS::Grammar::AST::Token;

    has Int $.line_no is rw = 1;
    has Int $!nl_highwater = 0;
    # variable encoding - not yet supported
    has $.encoding is rw = 'UTF-8';

    # accumulated warnings
    has @.warnings;

    method reset {
        @.warnings = ();
        $.line_no = 1;
        $!nl_highwater = 0;
    }

    method token(Mu $ast, :$skip, :$type, :$units) {

        return unless $ast.defined;

        $ast
            does CSS::Grammar::AST::Token
            unless $ast.can('type');

        $ast.skip = $skip if defined $skip;
        $ast.type = $type if defined $type;
        $ast.units = $units if defined $units;

        return $ast;
    }

    method node($/) {
        # make an intermediate node
        my %terms;

        for $/.caps -> $cap {
            my ($key, $value) = $cap.kv;
            $value = $value.ast;
            next unless $value.defined;
            die "repeated term: " ~ $key ~ " (use .list, implement custom method, or refactor grammar)"
                if %terms.exists($key);

            %terms{$key} = $value;
        }

        return %terms;
    }

    method at_rule($/) {
        my %terms = $.node($/);
        %terms<@> = $0.Str.lc;
        return %terms;
    }

    method list($/) {
        # make a node that contains repeatable elements
        my @terms;

        for $/.caps -> $cap {
            my ($key, $value) = $cap.kv;
            $value = $value.ast;
            next unless $value.defined;
            push @terms, ($key => $value);
        }

        return @terms;
    }

    sub _display_string($_str) {

        my $str = $_str.chomp.subst(/^<ws>/,'').subst(/<ws>$/,'');
        $str = $str.subst(/[\s|\t|\n|\r]+/, ' '):g;

        my %unesc = (
            "\n" => '\n',
            "\r" => '\t',
            "\f" => '\f',
            "\\"  => '\\',
            );

        $str.split('').map({
            %unesc{$_} // (
               $_ ~~ /<[\t\o40 \!..\~]>/ ?? $_ !! sprintf "\\x[%x]", $_.ord
            )
       }).join('');
    }

    method warning ($message, $str?, $explanation?) {
        my $warning = $message;
        $warning ~= ': ' ~ _display_string( $str )
            if $str.defined && $str ne '';
        $warning ~= ' - ' ~ $explanation
            if $explanation;
        $warning does CSS::Grammar::AST::Info;
        $warning.line_no = $.line_no;
        push @.warnings, $warning;
    }

    method nl($/) {
        my $pos = $/.from;

        return
            if my $_backtracking = $pos <= $!nl_highwater;

        $!nl_highwater = $pos;
        $.line_no++;
    }

    method element_name($/) {make $<ident>.ast}

    method any($/) {}

    method dropped_decl:sym<forward_compat>($/) {
        $.warning('dropping term', $0.Str)
            if $0.Str.chars;
        $.warning('dropping declaration', $<property>.ast);
    }

    method dropped_decl:sym<stray_terms>($/) {
        $.warning('dropping term', $0.Str);
    }

    method dropped_decl:sym<badstring>($/) {
        my $prop = $<property>>>.ast;
        if $prop {
            $.warning('dropping declaration', $prop);
        }
        elsif $0.Str.chars {
            $.warning('dropping term', $0.Str)
        }
    }

    method dropped_decl:sym<flushed>($/) {
        $.warning('dropping term', $0.Str);
    }

    method _to_unicode($str) {
        my $ord = $._from_hex($str);
        return Buf.new( $ord ).decode( $.encoding );
    }

    method unicode($/) {
       make $._to_unicode( $0.Str );
    }
    method nonascii($/){make $/.Str}
    method escape($/){make $<unicode> ?? $<unicode>.ast !! $<char>.Str}
    method nmstrt($/){
        make $0 ?? $0.Str !! ($<nonascii> || $<escape>).ast;
    }
    method nmchar($/){
        make $<nmreg> ?? $<nmreg>.Str !! ($<nonascii> || $<escape>).ast;
    }
    method ident($/) {
        my $pfx = $<pfx> ?? $<pfx>.Str !! '';
        make $pfx ~ $<nmstrt>.ast ~ $<nmchar>.map({$_.ast}).join('');
    }
    method name($/) {
        make $<nmchar>.map({$_.ast}).join('');
    }
    method notnum($/) { make $0.chars ?? $0.Str !! $<nonascii>.Str }
    method num($/) { make $/.Num }
    method posint($/) { make $/.Int }

    method stringchar:sym<cont>($/)     { make '' }
    method stringchar:sym<escape>($/)   { make $<escape>.ast }
    method stringchar:sym<nonascii>($/) { make $<nonascii>.ast }
    method stringchar:sym<ascii>($/)    { make $/.Str }

    method single_quote($/) {make "'"}
    method double_quote($/) {make '"'}

    method string($/) {
        my $string = $<stringchar>.map({ $_.ast }).join('');
        make $.token($string, :type('string'));
    }

    method badstring($/) {
        $.warning('unterminated string', $/.Str);
    }

    method id($/) { make $<name>.ast }
    method class($/) { make $<name>.ast }

    method url_char($/) {
        my $cap = $<escape> || $<nonascii>;
        make $cap ?? $cap.ast !! $/.Str
    }
    method url_string($/) {
        my $string = $<string> || $<badstring>;
        make $string
            ?? $string.ast
            !! $.token( $<url_char>.map({$_.ast}).join('') );
    }

    method url($/)  { make $<url_string>.ast }

    method color_arg($/) {
        my $arg = %<num>.ast;
        $arg = ($arg * 2.55).round
            if $<percentage>.Str;
        make $.token($arg, :type('num'), :units('4bit'));
    }

    method color:sym<rgb>($/)  {
        return $.warning('usage: rgb(c,c,c) where c is 0..255 or 0%-100%')
            unless $<ok>;
        make (rgb => $.node($/))
    }
    method color:sym<hex>($/)   {
        my $id = $<id>.ast;
        my $chars = $id.chars;
        unless $id.match(/^<xdigit>+$/)
            && ($chars == 3 || $chars == 6) {
                $.warning("bad hex color", $/.Str);
                return;
        }

        my @rgb = $chars == 3
            ?? $id.comb(/./).map({$_ ~ $_})
            !! $id.comb(/../);
        my %rgb;
        %rgb<r g b> = @rgb.map({$._from_hex( $_ )}); 
        make (rgb => %rgb);
    }

    method prio($/) {
        my ($any) = $<any>.list;
        if $any || !$0 {
            $.warning("dropping term", $/.Str);
            return;
        }

        make $0.Str.lc
    }

    # from the TOP (CSS1 + CSS21)
    method TOP($/) { make $<stylesheet>.ast }
    method stylesheet($/) { make $.list($/) }

    method charset($/)   { make $<string>.ast }
    method import($/)    { make $.node($/) }
    method namespace($/) { make $.node($/) }

    method misplaced($/) {
        $.warning('ignoring out of sequence directive', $/.Str)
    }
    method misplaced2($/) {
        $.warning('ignoring out of sequence directive', $/.Str)
    }

    method operator($/) { make $.token($/.Str, :type('operator')) }

    # pseudos
    method pseudo:sym<element>($/) { my %node; # :first-line
                                     %node<element> = $<element>.Str;
                                     make %node;
    }
    method pseudo:sym<element2>($/) { make $.node($/) }
    method pseudo:sym<function>($/) { make $.node($/) }
    method pseudo:sym<class>($/)    { make $.node($/) }

    # combinators
    method combinator:sym<adjacent>($/) { make $.token($/.Str) } # '+'
    method combinator:sym<child>($/)    { make $.token($/.Str) } # '>'
    method combinator:sym<not>($/)      { make $.token($/.Str) } # '-' css2.1
    method combinator:sym<sibling>($/)  { make $.token($/.Str) } # '~'

    # css2/css3 core - media support
    method at_rule:sym<media>($/) { make $.at_rule($/) }
    method media_rules($/)        { make $.list($/) }
    method media_list($/)         { make $.list($/) }
    method media_query($/)        { make $.list($/) }

    # css2/css3 core - page support
    method at_rule:sym<page>($/)  { make $.at_rule($/) }
    method page_pseudo($/)        { make $<ident>.ast }

    method property($/)           { make $<property>.ast }
    method ruleset($/)            { make $.node($/) }
    method selectors($/)          { make $.list($/) }
    method declarations($/)       { make $<declaration_list>.ast }
    method declaration_list($/)   { make $.list($/) }
    method declaration($/)        { 
        my %decl = $.node($/);

        unless @(%decl<expr>) {
            $.warning('dropping declaration', %decl<property>);
            return;
        }

        make %decl;
    }

    method expr($/) { make $.list($/, :keep_undef(True)) }

    method pterm:sym<quantity>($/) {
        my $type = 'num';
        my $units;

        my ($units_cap) = $<units>.list;
        if $units_cap {
            ($type, $units) = $units_cap.ast.kv;
            $units = $units.lc;
        }

        make $.token($<num>.ast, :type($type), :units($units));
    }

    method units:sym<length>($/)     { make (length => $/.Str.lc) }
    method units:sym<angle>($/)      { make (angle => $/.Str.lc) }
    method units:sym<time>($/)       { make (time => $/.Str.lc) }
    method units:sym<freq>($/)       { make (freq => $/.Str.lc) }
    method units:sym<percentage>($/) { make (percentage => $/.Str.lc) }
    method dimension($/)     {
        $.warning('unknown dimensioned quantity', $/.Str);
    }
    # treat 'ex' as '1ex'; 'em' as '1em'
    method pterm:sym<emx>($/)        { make $.token(1, :units($/.Str.lc), :type('length')) }

    method aterm:sym<string>($/)     { make $.token($<string>.ast, :type('string')) }
    method aterm:sym<url>($/)        { make $.token($<url>.ast, :type('url')) }
    method aterm:sym<color>($/)      {
        my ($units, $ast) = $<color>.ast.kv;
        make $.token($ast, :type('color'), :units($units))
            if $ast;
    }
    method aterm:sym<function>($/)   {
        make $.token($<function>.ast, :type('function'))
            if $<function>;
    }
    method aterm:sym<ident>($/)      { make $.token($<ident>.ast, :type('ident')) }

    method emx($/) { make $/.Str.lc }

    method term($/) {
        if $<term> {
            my $term_ast = $<term>.ast;
            if $<unary_operator> && $<unary_operator>.Str eq '-' {
                $term_ast = $.token( - $term_ast,
                                     :units($<term>.ast.units),
                                     :type($<term>.ast.type) );
            }
            make $term_ast;
        }
    }

    method selector($/)                          { make $.list($/) }
    method simple_selector($/)                   { make $.list($/) }
    method attrib($/)                            { make $.node($/) }
    method function:sym<counters>($/) {
        return $.warning('usage: counters(ident [, "string"])')
            unless $<ident>;
        make {ident => 'counter', args => $.list($/)}
    }
    method pseudo_function:sym<lang>($/)             {
        return $.warning('usage: lang(ident)')
            unless $<ident>;
        make {ident => 'lang', args => $.list($/)}
    }
    method unknown_function($/)             {
        $.warning('unknown function', $<ident>.ast);
    }
    method unknown_pseudo_func($/)             {
        $.warning('unknown pseudo-function', $<ident>.ast);
    }

    method attribute_selector:sym<equals>($/)    { make $/.Str }
    method attribute_selector:sym<includes>($/)  { make $/.Str }
    method attribute_selector:sym<dash>($/)      { make $/.Str }

    method unclosed_comment($/) {
        $.warning('unclosed comment at end of input');
    }

    method unclosed_paren($/) {
        $.warning("missing closing ')'");
    }

    method end_block($/) {
        $.warning("no closing '}'")
            unless $<closing_paren>;
    }

    # todo: warnings can get a bit too verbose here
    method unknown:sym<statement>($/) {$.warning('dropping', $/.Str)}
    method unknown:sym<flushed>($/)   {$.warning('dropping', $/.Str)}
    method unknown:sym<punct>($/)     {$.warning('dropping', $/.Str)}
    method unknown:sym<char>($/)      {$.warning('dropping', $/.Str)}

    # utiltity methods / subs

    method _from_hex($hex) {

        my $result = 0;

        for $hex.split('') {

            my $hex_digit;

            if ($_ ge '0' && $_ le '9') {
                $hex_digit = $_;
            }
            elsif ($_ ge 'A' && $_ le 'F') {
                $hex_digit = ord($_) - ord('A') + 10;
            }
            elsif ($_ ge 'a' && $_ le 'f') {
                $hex_digit = ord($_) - ord('a') + 10;
            }
            else {
                # our grammar shouldn't allow this
                die "illegal hexidecimal digit: $_";
            }

            $result *= 16;
            $result += $hex_digit;
        }
        return $result;
    }
}
