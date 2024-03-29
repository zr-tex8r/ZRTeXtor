#
# ZRTeXtor.pm : library for processing TeX font data
#
# Copyright (c) 2010-2021 Takayuki YATO (aka. "ZR")
#   GitHub:   https://github.com/zr-tex8r
#   Twitter:  @zr_tex8r
#
# This software is distributed under the MIT License.
#

######## start package
package ZRTeXtor;
use strict qw( refs vars subs );
require Exporter;
our $VERSION = 1.008_01;
our $mod_date = "2021/10/09";
our @ISA = qw( Exporter );
our @EXPORT = ();
our %EXPORT_TAGS = (
  'gen' => [qw(
    textool_error textool_version
    read_whole_file write_whole_file
    arraymap
    test1 test2 test3 debug_vf_form
  )],
  'pl' => [qw(
    pl_parse pl_parse_list pl_cook_list
    pl_form pl_form_list
    pl_value pl_set_value pl_set_numtype
    pl_prefer_hex
    pl_rearrange pl_clone pl_sclone
    pl_header pl_header_vpl pl_header_opl
    pl_fontdimen pl_fontdimen_jpl
    pl_fontdimen_opl_rmt pl_fontdimen_jpl_rmt
    pl_get_metric pl_char_part pl_char_part_jpl
  )],
  'x' => [qw(
    x_captured_exec
    x_tftopl x_uptftopl x_pltotf x_vptovf x_opl2ofm
  )],
  'jcode' => [qw(
    jcode_set jcode_chr jcode_ord
  )],
  'ps' => [qw(
    ps_parse0
  )],
  'enc' => [qw(
    enc_register enc_retrieve enc enc_parse enc_form
    ENCF_NORMAL ENCF_ANNOT ENCF_COMPACT ENCF_256
  )],
  'kpse' => [qw(
    kpse kpse_init
  )],
  'ttf' => [qw(
    ttf_generate_opl ttf_generate_jpl_x ttf_generate_jpl
    ttf_get_metric
  )],
  'tfm' => [qw(
    tfm_reduce_jpl_x tfm_reduce_jpl tfm_reduce
    tfm_reduced_metric tfm_map_rmt
  )],
  'vf' => [qw(
    vf_strict vf_simple_move_code
    vf_parse vf_form vf_parse_ex vf_form_ex
    vf_for_mapping vf_mapfont vf_set_mapfont
    vf_expand_named_charlist
  )],
  'jfm' => [qw(
    jfm_use_uptex_tool jfm_use_charlist_name
    jfm_parse jfm_form
  )],
);
our @EXPORT_OK = map { @{$_} } (values %EXPORT_TAGS);
$EXPORT_TAGS{all} = [ @EXPORT_OK ];
use Carp;
use Encode qw(encode decode);

######## general ########

our $binmode = 0;           # always read/write in binary mode
our $errmsg;                # last error message
use constant { HUGE => 1e20, EPS => 1e-7 };
  # TU = TFM factor, DU = DVI factor
use constant { TU => 1 << 20, DU => 1 << 16, B31 => 1 << 31 };
use constant { M32 => 0xFFFFFFFF, M31 => 0x7FFFFFFF };
use constant { # kanji encoding names
  K_JIS => 'iso-2022-jp', K_EUC => 'euc-jp',
  K_SJIS => 'shiftjis', K_UTF8 => 'UTF-8',
  KI_JIS => 'jis0208-raw', KI_UNI => 'UTF-16BE',
  KI_XJIS => '*xjis*', K_XJIS => '*xjis*',
};
# for get_temp_name
our $get_temp_base = '__zrtx';
our (@get_temp_id);

## error($msg, ...)
# Sets the error message and returns nothing (undef in scalar).
# Usually a defined value is returned in success.
sub error
{
  $errmsg = join('', map { (ref $_) ? '[obj]' : $_ } (@_));
  return;
}

## fatal($msg, ...)
# Intended for internal errors....
sub fatal
{
  return error("!!FATAL(", @_, ")");
}

##<*> textool_error()
# Obtains the error message of the last error. This string
# can be used in error handling of your own style.
sub textool_error
{
  return $errmsg;
}

##<*> textool_version()
# Returns the version information on this library.
sub textool_version
{
  my ($t, @fs);
  $t = sprintf("%.5f", $VERSION);
  (@fs = $t =~ m|^(\d+)\.(\d\d\d)(\d\d)$|)
    or return fatal("textool_version");
  $t = sprintf("%d.%d.%d", @fs);
  return ("$t", $mod_date);
}

## get_temp_name()
# Returns a temporary file name which is unique in the process.
# Note: Trailing digits in font names can have special meaning
# in some TeX tools.
sub get_temp_name
{
  ++$get_temp_id[0];
  return join('', $get_temp_base, $$, @get_temp_id[1, 0, 2]);
}

## get_temp_anme_init()
# Initializer for get_temp_name.
sub get_temp_name_init
{
  my ($t); $get_temp_id[0] = 0;
  $t = join('', map { ('a' .. 'z')[int(rand() * 26)] } (0 .. 5));
  @get_temp_id[1, 2] = map { substr($t, $_, 3) } (0, 3);
}

##<*> read_whole_file($fnam, $swbin)
# Reads in file $fnam and returns its content as a string.
# If $swbin or the global flag $binmode is true the file is read
# in binary mode.
sub read_whole_file
{
  my ($fnam, $swbin) = @_; my ($hf, $txt); local ($/);
  (defined $fnam) or return;
  open($hf, '<', $fnam)
    or return error("cannot open for read: $fnam");
  if ($binmode || $swbin) { binmode($hf); }
  $txt = readline($hf);
  close($hf);
  return $txt;
}

##<*> write_whole_file($fnam, $txt, $swbin)
# Creates (or crobbers) the file $fnam and write $txt to it.
# If $swbin or the global flag $binmode  is true it writes in
# binary mode.
sub write_whole_file
{
  my ($fnam, $txt, $swbin) = @_; my ($hf);
  open($hf, '>', $fnam)
    or return error("cannot open for write: $fnam");
  if ($binmode || $swbin) { binmode($hf); }
  print $hf ($txt);
  close($hf);
  return 1;
}

## unpack_num($s)
# Decodes a unsigned number in big-endian string.
sub unpack_num
{
  my ($s) = @_;
  return unpack("N", substr("\0\0\0\0$s", length($s)));
}

## unpack_snum($s)
# Decodes a signed number in big-endian string.
my @snum_bound = (0, 0x80, 0x8000, 0x800000, B31);
sub unpack_snum
{
  my ($s) = @_; my ($b, $v);
  $b = $snum_bound[length($s)];
  $v = unpack("N", substr("\0\0\0\0$s", length($s)));
  return ($v >= $b) ? ($v - $b - $b) : $v;
}

## pack_num($v)
# Encodes a unsigned number in big-endian string, with the length
# prefix. In scalar context the returned values are concatenated.
sub pack_num
{
  my ($v) = @_; my ($t, $l);
  ($t = pack('N', $v)) =~ s/^\0{1,3}//; $l = length($t);
  return (wantarray) ? ($l, $t) : (chr($l) . $t);
}

## pack_snum($v)
# Signed version of pack_num.
sub pack_snum
{
  my ($v) = @_; my ($t, $l);
  ($t = pack('N', $v)) =~
    s/^\0{1,3}([\x00-\x7f])|^\xff{1,3}([\x80-\xff])/$+/;
  $l = length($t);
  return (wantarray) ? ($l, $t) : (chr($l) . $t);
}

## signed($v)
# Converts 'unsigned long' to 'signed long'.
sub signed
{
  my ($v) = @_; $v &= M32;
  return ($v >= B31) ? ($v - B31 - B31) : $v;
}

## round($v)
# Rounds a real value to an integer.
sub round
{
  my ($v) = @_;
  return int($v + (($v < 0) ? -0.5 : +0.5));
}

##<*> arraymap($map, $swmm)
# Converts a code map in hash form into array form.
sub arraymap
{
  my ($map, $swmm) = @_; my ($sc, $dc, @u, @amap);
  if (ref $map eq 'HASH') {
    @u = sort { $a <=> $b } (keys %$map);
    foreach $sc (@u) {
      $dc = $map->{$sc};
      if (ref $dc eq 'ARRAY') {
        if ($swmm) {
          foreach (@$dc) { push(@amap, [$sc, $_]); }
        } else { push(@amap, [$sc, $dc->[0]]); }
      } elsif (defined $dc) { push(@amap, [$sc, $dc]); }
    }
    return \@amap;
  } elsif (ref $map eq 'ARRAY') { return $map; }
  else { return; }
}

## squote($str)
# S-quotes a string.
sub squote
{
  my ($str) = @_; $str =~ s/([\\\'])/\\$1/g;
  return "'$str'";
}

## zdquote($str)
# ZD-quotes a string.
sub zdquote
{
  my ($str) = @_; $str =~ s/([\\\"])/\\$1/g;
  $str =~ s/([^\x20-\x7e])/sprintf("\\%02X",$1)/ge;
  return "\"$str\"";
}

######## 'x' section ########

use IPC::Open3; # for open3()
our %cmd_name = (
  kpsewhich => 'kpsewhich',
  tftopl => 'ptftopl',
  pltotf => 'ppltotf',
  uptftopl => 'uptftopl',
  uppltotf => 'uppltotf',
  vftovp => 'vftovp',
  vptovf => 'vptovf',
  opl2ofm => 'opl2ofm',
);

##<*> x_captured_exec(@cmd);
# Spawns the command @cmd, captures its stdout and stderr into
# strings, and returns them.
# --- Am I doing right?
sub x_captured_exec
{
  my (@cmd) = @_; my ($pid, @fs, @ds);
  local(*CHIN, *CHOUT, *CHERR, $/);
  L1:{
    @fs = (get_temp_name(), get_temp_name());
    open(CHOUT, '+>', $fs[0]) or last;
    open(CHERR, '+>', $fs[1]) or last;
    ($pid = open3(\*CHIN, '>&CHOUT', '>&CHERR', @cmd)) or last;
    waitpid($pid, 0);
    seek(CHOUT, 0, 0); $ds[0] = <CHOUT>;
    seek(CHERR, 0, 0); $ds[1] = <CHERR>;
  }
  close(CHIN); close(CHOUT); close(CHERR);
  unlink(@fs);
  return (@ds);
}

##<*> x_tftopl
# Wrapper for 'tftopl' command.
sub x_tftopl
{
  my ($tfm, $cmd) = @_; my ($ftmp, $ftfm, $fpl, $cout, $cerr);
  if (!defined $cmd) { $cmd = $cmd_name{tftopl}; }
  if ($tfm =~ m/\.tfm$/i && $tfm !~ /\0/) { $ftfm = $tfm; }
  else {
    $ftfm = $ftmp = get_temp_name() . ".tfm";
    (write_whole_file($ftmp, $tfm, 1)) or return;
  }
  $fpl = get_temp_name() . ".pl";
  ($cout, $cerr) = x_captured_exec("$cmd $ftfm $fpl");
  if (defined $ftmp) { unlink($ftmp); }
  $cout = read_whole_file($fpl); unlink($fpl);
  if ($cout eq '' || $cout =~ /CHANGED!\)\s*$/) {
    return error("tftopl failed: $ftfm");
  }
  return pl_parse($cout);
}

##<*> x_uptftopl
# Wrapper for 'uptftopl' command.
# Use of x_tftopl($tfm, "uptftopl") does not seem to work right.
# Perhaps getting uptftopl to 'output to terminal' confuses
# uptftopl as to handling UTF-8 strings....
sub x_uptftopl
{
  my ($tfm, $cmd) = @_; my ($ftmp, $ftfm, $fpl, $cout, $cerr);
  if (!defined $cmd) { $cmd = $cmd_name{uptftopl}; }
  if ($tfm =~ m/\.tfm$/i && $tfm !~ /\0/) { $ftfm = $tfm; }
  else {
    $ftfm = $ftmp = get_temp_name() . ".tfm";
    (write_whole_file($ftmp, $tfm, 1)) or return;
  }
  $fpl = get_temp_name() . ".pl";
  ($cout, $cerr) = x_captured_exec("$cmd $ftfm $fpl");
  if (defined $ftmp) { unlink($ftmp); }
  $cout = read_whole_file($fpl); unlink($fpl);
  if ($cout eq '' || $cout =~ /CHANGED!\)\s*$/) {
    return error("tftopl failed: $ftfm");
  }
  if ($cout =~ m/CHARSINTYPE/) { $cout = pl_adjust_lit_paren($cout); }
  return pl_parse($cout);
}

##<*> x_pltotf
# Wrapper for 'pltotf' command.
sub x_pltotf
{
  my ($pl, $cmd) = @_;
  my ($ftmp, $fpl, $cout, $ftfm, $tfm, $tn);
  if (!defined $cmd) { $cmd = $cmd_name{pltotf}; }
  $tn = get_temp_name(); $ftfm = "$tn.tfm";
  if (ref $pl eq 'ARRAY') { $pl = pl_form($pl); }
  if ($pl =~ m/\.pl$/i) { $fpl = $pl; }
  else {
    $fpl = $ftmp =  "$tn.pl";
    (write_whole_file($ftmp, $pl)) or return;
  }
  $cout = `$cmd $fpl $ftfm`;  # no output to stderr
  if (defined $ftmp) { unlink($ftmp); }
  (-f $ftfm) or return error("pltotf failed: $fpl");
  $tfm = read_whole_file($ftfm, 1); unlink($ftfm);
  foreach (split(/\n/, $cout)) {
    if (m/^\s*$/ || m/^I had to round some / ||
        m/Input file is in kanji /) { next; }
    return error("pltotf failed: $fpl");
  }
  return $tfm;
}

##<*> x_vptovf
# Wrapper for 'vptovf' command.
sub x_vptovf
{
  my ($pl, $cmd) = @_;
  my ($ftmp, $fpl, $cout, $ftfm, $tfm, $fvf, $vf, $tn);
  if (!defined $cmd) { $cmd = $cmd_name{vptovf}; }
  $tn = get_temp_name(); $ftfm = "$tn.tfm"; $fvf = "$tn.vf";
  if (ref $pl eq 'ARRAY') { $pl = pl_form($pl); }
  if ($pl =~ m/\.vpl$/i) { $fpl = $pl; }
  else {
    $fpl = $ftmp =  "$tn.vpl";
    (write_whole_file($ftmp, $pl)) or return;
  }
  $cout = `$cmd $fpl $fvf $ftfm`;  # no output to stderr
  if (defined $ftmp) { unlink($ftmp); }
  (-f $ftfm && -f $fvf) or return error("vptovf failed: $fpl");
  $tfm = read_whole_file($ftfm, 1); unlink($ftfm);
  $vf = read_whole_file($fvf, 1); unlink($fvf);
  foreach (split(/\n/, $cout)) {
    if (m/^\s*$/ || m/^I had to round some / ||
        m/Input file is in kanji / || m/LIG/) { next; }
    return error("vptovf failed: $fpl");
  }
  return ($vf, $tfm);
}

##<*> x_opl2ofm
# Wrapper for 'opl2ofm' command.
sub x_opl2ofm
{
  my ($pl) = @_; my ($cmd, $ftmp, $fpl, $cout, $ftfm, $tfm, $tn);
  $tn = get_temp_name(); $ftfm = "$tn.ofm";
  if (ref $pl eq 'ARRAY') { $pl = pl_form($pl); }
  if ($pl =~ m/\.opl$/i) { $fpl = $pl; }
  else {
    $fpl = $ftmp =  "$tn.opl";
    (write_whole_file($ftmp, $pl)) or return;
  }
  $cmd = $cmd_name{opl2ofm};
  $cout = `$cmd $fpl $ftfm`;  # no output to stderr
  if (defined $ftmp) { unlink($ftmp); }
  (-f $ftfm) or return error("opl2ofm failed: $fpl");
  $tfm = read_whole_file($ftfm, 1); unlink($ftfm);
  foreach (split(m/\n/, $cout)) {
    if (m/^\s*$/ || m/^I had to round some / ||
        m/Input file is in kanji /) { next; }
    return error("opl2ofm failed: $fpl");
  }
  return $tfm;
}


######## 'pl' section ########

####---- Handling General Property Lists

# * Data structure: pl-list, pl-struct
# A PL Text consists of a sequence of Lispish lists (without the
# outermost parentheses). In 'raw' structures, Lispish lists are
# represented by Perl arrays with straightforward conversion
# (all atomic elements are strings). Such an array is  called
# 'pl-list' here. The entire PL is represented as an array of
# pl-lists, called 'pl-struct' here.
# However, in 'cooked' structures, some numerical data are
# interpreted. For example, raw data
#    'D', '0100'   (a part of a pl-list)
# are cooked they change to
#    [ CNUM, 100, 'D' ], '0100'
# and moreover the assignment of 500 to this part results in
#    [ CNUM, 500, 'D' ], undef
# And its conversion back into text is 'O 764', because 500 cannot
# be expressed in 'D' notation.

use constant CNUM => ' ';   # flag signifying a cooked number
our $freenum = 0;

my %pl_facecode = (         # 'F' notation
  MRR => 0, MIR => 1, BRR => 2, BIR => 3, LRR => 4, LIR => 5,
  MRC => 6, MIC => 7, BRC => 8, BIC => 9, LRC => 10, LIC => 11,
  MRE => 12, MIE => 13, BRE => 14, BIE => 15, LRE => 16, LIE => 17
);
my %pl_facecode_rev = (reverse %pl_facecode);

##<*> pl_parse($txt)
# Converts a PL text $txt to a 'cooked' pl-struct.
sub pl_parse
{
  my ($txt) = @_; my ($pl, $ent);
  (defined($pl = pl_parse_list("($txt)"))) or return;
  (pl_cook_list($pl)) or return;
  foreach $ent (@$pl) {
    if (!ref $ent) { return error("bareword found: ", $ent); }
  }
  return $pl;
}

##<*> pl_parse_list($txt)
# Converts a text $txt of a Lispish list to a 'raw' pl-list.
sub pl_parse_list
{
  my ($txt) = @_; my (@toks, $pp, $t, $swjis);
  if (($swjis = $txt =~ m/\x1B\x24/)) { $txt = pl_conv_jis_out($txt); }
  @toks = grep { $_ ne "" } (split(/(\()|(\))|\s+/, $txt));
  if ($swjis) {
    foreach (@toks) {
      if (m/[\x80-\xff]/) { $_ = pl_conv_jis_in($_); }
    }
  }
  if ($toks[0] ne '(') { return error("missing paren at top"); }
  $pp = pl_corres_paren(\@toks, 0);
  if ($pp == $#toks) {
    return pl_parse_sub(\@toks, 1, $pp - 1);
  } elsif ($pp < 0) {
    return error("unmatched parens (end at level ", -$pp, ")");
  } else {
    return error("unmatched parens (extra tokens)");
  }
}
sub pl_conv_jis_out {
  my ($txt) = @_; my ($t, $pos, @cnks);
  $pos = pos($txt) = 0;
  while ($txt =~
    m/(\x1B\x24[\x42\x40]([\x21-\x7E]+)\x1B\x28[\x42\x4A])/g) {
    ($t = $2) =~ tr/\x21-\x7E/\xA1-\xFE/;
    push(@cnks, substr($txt, $pos, pos($txt) - length($1) - $pos), $t);
    $pos = pos($txt);
  }
  return join('', @cnks, substr($txt, $pos));
}
sub pl_conv_jis_in {
  my ($txt) = @_; my ($t, $pos, @cnks);
  $pos = pos($txt) = 0;
  while ($txt =~ m/([\xA1-\xFE]+)/g) {
    ($t = $1) =~ tr/\xA1-\xFE/\x21-\x7E/;
    push(@cnks, substr($txt, $pos, pos($txt) - length($1) - $pos),
         "\x1B\x24\x42$t\x1B\x28\x42");
    $pos = pos($txt);
  }
  return join('', @cnks, substr($txt, $pos));
}

## pl_adjust_lit_paren($pl)
sub pl_adjust_lit_paren
{
  my ($pl) = @_; my ($mod, $repl, $lin, @lins);
  @lins = split(m/\n/, $pl);
  foreach (0 .. $#lins) {
    $lin = $lins[$_];
    if ($mod == 2) {
      if ($lin =~ m/^\s*\)\s*$/) {
        $lins[$_ - 1] =~ s/\)/X0029/; $repl = 1;
      }
      $mod = 0;
    } elsif ($mod == 1) {
      if ($lin =~ m/^\s*\)\s*$/) { $mod = 2; }
      else {
        if ($lin =~ m/\(/) { $lins[$_] =~ s/\(/X0028/g; $repl = 1; }
        if ($lin =~ m/\)/) { $lins[$_] =~ s/\)/X0029/g; $repl = 1; }
        if ($lin =~ m/\bU [\dA-F]{4}/) {
          $lins[$_] =~ s/\bU ([\dA-F]{4})/U$1/g; $repl = 1;
        }
      }
    }
    if ($lin =~ m/^\(CHARSINTYPE /) { $mod = 1; }
  }
  return ($repl) ? join("\n", @lins) : $pl;
}

## pl_parse_sub(...)
# Subcontractor of pl_parse_list.
sub pl_parse_sub
{
  my ($toks, $sp, $ep) = @_; my (@pl, $tok, $p, $pp, $pl2);
  for ($p = $sp; $p <= $ep; $p++) {
    $tok = $toks->[$p];
    if ($tok eq '(') {
      $pp = pl_corres_paren($toks, $p);
      ($p < $pp && $pp <= $ep) or return fatal(0);
      (defined($pl2 = pl_parse_sub($toks, $p + 1, $pp - 1))) or return;
      push(@pl, $pl2); $p = $pp;
    } else {
      push(@pl, $tok);
    }
  }
  return \@pl;
}

## pl_corres_paren($toks, $p)
# Returns the index of the ')' token which corresponds with the
# '(' token at index $p in an array $toks.
sub pl_corres_paren
{
  my ($toks, $p) = @_; my ($tok, $lv);
  for ($lv = 1, ++$p; $p <= $#$toks; $p++) {
    $tok = $toks->[$p];
    if ($tok eq '(') { ++$lv; }
    elsif ($tok eq ')') { --$lv; }
    if ($lv == 0) { last; }
  }
  return ($lv > 0) ? -$lv : $p;
}

##<*> pl_cook_list($pl)
# Makes a raw pl-list $pl cooked.
sub pl_cook_list
{
  my ($pl) = @_; my ($k, $ent, $res);
  for ($k = 0; $k <= $#$pl; $k++) {
    $ent = $pl->[$k];
    if (ref $ent) {
      if ($ent->[0] eq 'COMMENT') {
        splice(@$pl, $k, 1); redo;
      } elsif ($ent->[0] ne CNUM) {
        (pl_cook_list($ent)) or return;
      }
    } elsif ($ent =~ /^[CKDFOHR]$/ && $k < $#$pl) {
      (defined pl_proc_num($pl, $k)) or return;
      ++$k;
    }
  }
  return $pl;
}

##<*> pl_form($pl, $ind)
# Converts a pl-struct $pl into a PL text. Here $ind is the amount
# of indent: if negative the result is in in-line form.
sub pl_form
{
  my ($pl, $ind) = @_; my (@cnks, $ent, $txt);
  foreach $ent (@$pl) {
    (defined($txt = pl_form_list($ent, $ind))) or return;
    push(@cnks, $txt);
  }
  if ($ind >= 0) { return join("\n", @cnks, ''); }
  else { return join(' ', @cnks); }
}

# for pl_form_list
my $pl_rx_kent = qr/^[^\x20-\x7e]|^[JUX][0-9A-Fa-f]{4,6}$/;

##<*> pl_form_list($pl, $ind)
# Converts a pl-list $pl into a Lispish list.
sub pl_form_list
{
  my ($pl, $ind) = @_; my (@cnks, @lins, @toks);
  my ($k, $t, $lsepp, $lsep, $ent, $tok, $txt);
  if ($ind >= 0) {
    push(@cnks, '('); $ind += 3;
    $lsepp = $lsep = "\n" . ' ' x $ind;
  } else { push(@cnks, '('); $lsepp = $lsep = ' '; }
  for ($k = 0; $k <= $#$pl; $k++) {
    $ent = $pl->[$k];
    if (ref $ent) {
      if ($ent->[0] eq CNUM) {
        $tok = $pl->[$k + 1]; ++$k;
        if (defined $tok) { push(@lins, $ent->[2], $tok); }
        else {
          (@toks = pl_form_num($ent->[2], $ent->[1])) or return;
          push(@lins, @toks);
        }
      } else {
        if (@lins) { push(@cnks, join(' ', @lins), $lsepp); }
        (defined($txt = pl_form_list($ent, $ind))) or return;
        @lins = (); push(@cnks, $txt, $lsep);
      }
    } elsif ($k > 0 && $ind >= 0 && $ent =~ m/$pl_rx_kent/) {
      if (@lins) { push(@cnks, join(' ', @lins), $lsepp); }
      $t = '';
      while ($pl->[$k] =~ m/$pl_rx_kent/) {
        if (length($t) + length($pl->[$k]) + $ind > 72) { last; }
        $t .= $pl->[$k] . ' '; ++$k;
      }
      --$k; chop($t); @lins = (); push(@cnks, $t, $lsep);
    } else { push(@lins, $ent); }
  }
  push(@cnks, join(' ', @lins), ')');
  if ($ind < 0 && $cnks[-3] eq $lsep) { $cnks[-3] = ''; }
  return join('', @cnks);
}

##<*> pl_value($pl, $k, $sw)
# Reads the number at position $k in pl-list $pl. Note that
# $k is the position of form prefix and not the string represeting
# the nubmer itself.
# The value will be rounded to integers unless $sw is true.
sub pl_value
{
  my ($pl, $k, $sw) = @_; my ($ent);
  $ent = $pl->[$k];
  if (ref $ent && $ent->[0] eq CNUM) {
    return ($sw) ? $ent->[1] : round($ent->[1]);
  }
  return pl_proc_num($pl, $k);
}

## pl_proc_num($pl, $k)
# Converts the number token at position $k in pl-list $pl to
# cooked form.
sub pl_proc_num
{
  my ($pl, $k) = @_; my ($v, $fl, $tok);
  ($fl, $tok) = ($pl->[$k], $pl->[$k + 1]);
  if (defined($v = pl_parse_num($fl, $tok))) {
    $pl->[$k] = [ CNUM, $v, $fl ]; return $v;
  } else {
    return error("malformed number (", $fl, " ", $tok, ")");
  }
}

##<*> pl_set_value($pl, $k, $v)
# Changes the number at position $k in pl-list $pl to $v.
sub pl_set_value
{
  my ($pl, $k, $v) = @_; my ($ent);
  $ent = $pl->[$k];
  (ref $ent && $ent->[0] eq CNUM)
    or return error("illegal assignment", $ent);
  $pl->[$k + 1] = undef; $ent->[1] = $v;
  return 1;
}

##<*> pl_set_real($pl, $k)
# Changes the 'R'-form number at position $k in pl-list $pl to
# $v, which is a non-scaled value.
sub pl_set_real
{
  my ($pl, $k, $v) = @_; my ($ent);
  $ent = $pl->[$k];
  (ref $ent && $ent->[0] eq CNUM && $ent->[2] eq 'R')
    or return error("illegal assignment", $ent);
  $pl->[$k + 1] = undef; $ent->[1] = $v * TU;
  return 1;
}

##<*> pl_set_value($pl, $k, $v)
# Changes the form prefix of the number at position $k in
# pl-list $pl to $v.
sub pl_set_numtype
{
  my ($pl, $k, $v) = @_; my ($ent);
  $ent = $pl->[$k];
  (ref $ent && $ent->[0] eq CNUM)
    or return error("illegal assignment", $ent);
  $pl->[$k + 1] = undef; $ent->[2] = $v;
  return 1;
}


##<*> pl_prefer_hex($sw)
# Sets the value of the global flag $pl_prefer_hex. If its value is
# true, then 'H' (instead of 'O') is used as a fallback of 'D'/'C'.
our $pl_prefer_hex = 0;
sub pl_prefer_hex { $pl_prefer_hex = $_[0]; }

## pl_parse_num($fl, $tok)
# Converts a number token to the number it expresses. Here $fl is
# a form prefix and $tok is a token,
sub pl_parse_num
{
  my ($fl, $tok) = @_; my ($ll, $ul, $v);
  $ll = 0; $ul = M32;
  if (ref $tok) { return; }
  if ($fl eq 'C') {
    $v = ($tok =~ /^[\x21-\x7e]$/ && ord($tok));
  } elsif ($fl eq 'K') {
    $v = jcode_ord($tok);
  } elsif ($fl eq 'D') {
    $v = ($tok =~ /^-?\d+$/ && $tok); $ul = 255;
  } elsif ($fl eq 'F') {
    $v = (exists $pl_facecode{$tok} && $pl_facecode{$tok});
  } elsif ($fl eq 'O') {
    $v = ($tok =~ /^[0-7]+$/ && oct($tok)); $ul = M32;
  } elsif ($fl eq 'H' || $fl eq 'I') {
    $v = ($tok =~ /^[\da-f]+$/i && hex($tok)); $ul = M32;
  } elsif ($fl eq 'R') {
    $v = ($tok =~ /^[\+\-]?(\d*\.)?\d+$/ && pl_scale_real($tok));
    $ll = - B31; $ul = M31;
  }
  if ($freenum && $fl ne 'R') { $ul = M32; $ll = -$ul; }
  if (!($ll <= $v && $v <= $ul)) { $v = undef; }
  return $v;
}

## pl_form_num($fl, $v)
# Expresses the number $v in form $fl. If the number cannot (or
# should not) be expressed in form $fl, then $fl is fallen back
# to another suitable value. It returns ($fl, $tok) where $tok
# is the resulted expression and $fl is the possibly adapted
# value of form prefix.
sub pl_form_num
{
  my ($fl, $v) = @_; my ($tok);
  $tok = $fl;
  if ($fl eq 'F' && $v > 17) { $fl = 'D'; }
  if ($fl eq 'C' && !pl_isprint($v)) { $fl = 'I'; }
  if ($fl eq 'K' && (!pl_isjprint($v))) { $fl = 'H'; }
  if ($fl eq 'D' && $v > 255) { $fl = 'I'; }
  if ($fl eq 'I') { $fl = ($pl_prefer_hex) ? 'H' : 'O'; }
  if (($fl eq 'R' && !(- B31 <= $v && $v <= M31))
      || ($fl ne 'R' && !(0 <= $v && $v <= M32))) {
    return error("number is out of range ($v for $tok)");
  }
  if ($fl eq 'C') { $tok = chr($v); }
  elsif ($fl eq 'K') { $tok = jcode_chr($v); }
  elsif ($fl eq 'D') { $tok = $v; }
  elsif ($fl eq 'F') { $tok = $pl_facecode_rev{$v}; }
  elsif ($fl eq 'O') { $tok = sprintf("%o", $v); }
  elsif ($fl eq 'H') { $tok = sprintf("%X", $v); }
  elsif ($fl eq 'R') { $tok = pl_form_real($v / TU); }
  return ($fl, $tok);
}

# Note: In PL, big numbers (>255) in decimal are not allowed,
#   whereas they are allowed in VPL.

## pl_form_real($a)
# Expresses a real number in the same way as in PL.
sub pl_form_real
{
  my ($a) = @_; my ($d, @t);
  if ($a < -0.5 / TU) { $a = -$a; @t = ("-"); }
  $a = int($a * TU + 0.5);
  { use integer;
    push(@t, $a / TU, "."); $a %= TU;
    $a = $a * 10 + 5; $d = 10;
    do {
      if ($d > 0x100000) { $a = $a + 0x80000 - $d / 2; }
      push(@t, $a / 0x100000); $a = $a % 0x100000 * 10; $d *= 10;
    } until ($a <= $d);
  }
  return join('', @t);
}

## pl_scale_real($a)
# Returns a real value scaled to tfm-unit, rounded to integer.
sub pl_scale_real
{
  my ($a) = @_;
  return int($a * TU + (($a < 0) ? -0.5 : +0.5));
}


## pl_isprint($c)
# Tests if the number $c is to output really in 'C' form.
sub pl_isprint
{
  my ($c) = @_;
  return (0 <= $c && $c <= 255 && chr($c) =~ /^\w/);
}

## pl_isjprint($c)
# Tests if the number $c is to output in 'K' form.
sub pl_isjprint
{
  my ($c) = @_;
  return defined(jcode_chr($c));
}

####---- Rearranging pl-structs

##<*> pl_rearrange($pl)
# Sorts the pl-lists in a pl-struct $pl so that they are in
# 'usual' order.
sub pl_rearrange
{
  my ($pl) = @_;
  @$pl = sort { pl_prop_pos($a) <=> pl_prop_pos($b) } (@$pl);
  return $pl;
}

# for pl_prop_pos
my %pl_prop_pos_base = (
#  0xZ0001  --> 0xZXXXXXX
#  0xZ0002  --> 0xZXX0000
#  0xZ0003  --> 0xZXXYYYY
  DIRECTION         => 0x0000010,
  VTITLE            => 0x0000011,
  FAMILY            => 0x0000012,
  FACE              => 0x0000013,
  HEADER            => 0x1000001,
  CODINGSCHEME      => 0x2000010,
  DESIGNUNITS       => 0x2000011,
  DESIGNSIZE        => 0x2000012,
  CHECKSUM          => 0x2000013,
  SEVENBITSAFEFLAG  => 0x2000014,
  FONTDIMEN         => 0x2000015,
  BOUNDARYCHAR      => 0x2000016,
  MAPFONT           => 0x3000001,
  LIGTABLE          => 0x4000010,
  GLUEKERN          => 0x4000010,
  CODESPACE         => 0x5000000,
  CHARSINTYPE       => 0x5000002,
  CHARSINSUBTYPE    => 0x5000003,
  TYPE              => 0x6000002,
  SUBTYPE           => 0x6000003,
  CHARACTER         => 0x7000001,
);

## pl_prop_pos($pl)
# Subcontractor for pl_rearrange.
sub pl_prop_pos
{
  my ($pl) = @_; my ($v, $u);
  $v = $pl_prop_pos_base{$pl->[0]};
  if (!defined $v) { return 0xFFFFFFF; }
  $u = ($v & 0xffffff);
  if ($u == 1) {
    return ($v & 0xf000000) | pl_value($pl, 1);
  } elsif ($u == 2) {
    return ($v & 0xf000000) | (pl_value($pl, 1) << 16);
  } elsif ($u == 3) {
    return ($v & 0xf000000) | (pl_value($pl, 1) << 16) | pl_value($pl, 3);
  } else { return $v; }
}

####---- Rearranging pl-lists

##<*> pl_clone($pl)
# Returns a deep clone of a pl-list, where the original and the
# clone share no reference.
sub pl_clone
{
  my ($pl) = @_;
  if (ref $pl eq "ARRAY") {
    return [ map { pl_clone($_) } (@$pl) ];
  } else { return $pl; }
}

##<*> pl_sclone($pl)
# Returns a one-level clone of a pl-list, considering cooked
# number forms which should be uniquified.
sub pl_sclone
{
  my ($pl) = @_;;
  if (ref $pl eq "ARRAY") {
    return [ map {
              (ref $_ eq "ARRAY" && $_->[0] eq CNUM) ? [ @$_ ] : $_
             } (@$pl) ];
  } else { return $pl; }
}


####---- Handling PL/JPL/OPL/VPL Structs

# The three functions below generate a header part (stuffs before
# FONTDIMEN and optionally FONTDIMEN). Here $in is a hash ref with
# the following effective keys:
#   direction, family, vtitle, face, codingscheme, designunits,
#   designsize, checksum, sevenbitsafeflag, boundarychar
# they each correspond with the property of the same name. Of them
# 'designsize' has the default value 10, but it can be cancelled
# by 'designsize' key with the explicit undef value.
# If $fd is not undef, it specifies FONTDIMEN list: if $fd is an
# array ref it is seen as pl-list of FONTDIMEN and placed inside
# the output pl-list; if $fd is a hash ref then pl_fontdimen($fd)
# is placed instead.
# Note: currently these three functions give the same result.

##<*> pl_header($in, $fd)
sub pl_header
{ return pl_header_gen($_[0], $_[1], 0); }

##<*> pl_header_vpl($in, $fd)
sub pl_header_vpl
{ return pl_header_gen($_[0], $_[1], 8); }

##<*> pl_header_opl($in, $fd, $swl1)
sub pl_header_opl
{ return pl_header_gen($_[0], $_[1], ($_[2]) ? 2 : 1); }

## pl_header_gen($in, $fd, $sw)
# Subcontractor for the above three pl_header_* functions.
sub pl_header_gen
{
  my ($in, $fd, $sw) = @_; my ($t, $pe, $dsiz, $ol, @pl);
  if (exists $in->{ofmlevel}) { $ol = $in->{ofmlevel}; }
  elsif ($sw == 1 || $sw == 2) { $ol = $sw - 1; }
  $dsiz = (exists $in->{designsize}) ? $in->{designsize} : 10;
  if (defined $ol) {
    $pe = pl_cook(['OFMLEVEL', 'H', $ol]);
    pl_set_value($pe, 1, $ol); push(@pl, $pe);
  }
  if (defined $in->{direction}) {
    push(@pl, ['DIRECTION', $in->{direction}]);
  }
  if (defined $in->{family}) {
    push(@pl, ['FAMILY', $in->{family}]);
  }
  if (defined $in->{vtitle}) {
    push(@pl, ['VTITLE', $in->{vtitle}]);
  }
  if (defined $in->{face}) {
    $pe = pl_cook(['FACE', 'F', 0]);
    pl_set_value($pe, 1, $in->{face}); push(@pl, $pe);
  }
  if (defined $in->{codingscheme}) {
    push(@pl, ['CODINGSCHEME', $in->{codingscheme}]);
  }
  if (defined $in->{designunits}) {
    $pe = pl_cook(['DESIGNUNITS', 'R', 0]);
    pl_set_real($pe, 1, $in->{designunits}); push(@pl, $pe);
  }
  if (defined $dsiz) {
    $pe = pl_cook(['DESIGNSIZE', 'R', 0]);
    pl_set_real($pe, 1, $dsiz); push(@pl, $pe);
  }
  if (defined $in->{checksum}) {
    $pe = pl_cook(['CHECKSUM', 'O', 0]);
    pl_set_value($pe, 1, $in->{checksum}); push(@pl, $pe);
  }
  if (defined $in->{sevenbitsafeflag}) {
    push(@pl, ['SEVENBITSAFEFLAG', $in->{sevenbitsafeflag}]);
  }
  if (ref $fd eq 'ARRAY') {
    push(@pl, $fd);
  }
  if (ref $fd eq 'HASH') {
    push(@pl, pl_fontdimen($fd));
  }
  if (defined $in->{boundarychar}) {
    $pe = pl_cook(['BOUNDARYCHAR', 'C', 0]);
    pl_set_value($pe, 1, $in->{boundarychar}); push(@pl, $pe);
  }
  return \@pl;
}

##<*> pl_fontdimen($in)
# Generates a FONTDIMEN list. $in is a hash ref with the following
# effective keys:
#   slant, space, stretch, shrink, xheight, quad, extraspace;
# they each correspond with the property of the same name. All
# of them have a default value.
sub pl_fontdimen
{
  my ($in) = @_; my ($q, $t, $pl);
  (defined $in) or $in = { };
  $pl = pl_cook(['FONTDIMEN',
         ['SLANT', 'R', 0], ['SPACE', 'R', 0],
         ['STRETCH', 'R', 0], ['SHRINK', 'R', 0],
         ['XHEIGHT', 'R', 0], ['QUAD', 'R', 0],
         ['EXTRASPACE', 'R', 0]]);
  $q = $in->{quad}; (defined $q) or $q = 1;
  pl_set_real($pl->[6], 1, $q);
  $t = $in->{slant}; (defined $t) or $t = 0;
  pl_set_real($pl->[1], 1, $t);
  $t = $in->{space}; (defined $t) or $t = $q / 3;
  pl_set_real($pl->[2], 1, $t);
  $t = $in->{stretch}; (defined $t) or $t = $q / 6;
  pl_set_real($pl->[3], 1, $t);
  $t = $in->{shrink}; (defined $t) or $t = $q / 9;
  pl_set_real($pl->[4], 1, $t);
  $t = $in->{xheight}; (defined $t) or $t = $q / 2;
  pl_set_real($pl->[5], 1, $t);
  $t = $in->{extraspace}; (defined $t) or $t = $q / 9;
  pl_set_real($pl->[7], 1, $t);
  return $pl;
}

##<*> pl_fontdimen_jpl($in)
# Generates a FONTDIMEN list of JPL. Here $in is the same as in
# pl_fontdimen, except that two additional keys 'extrastretch'
# and 'extrashrink' are used and default setting is different.
sub pl_fontdimen_jpl
{
  my ($in) = @_; my ($q, $t, $pl);
  (defined $in) or $in = { };
  $pl = pl_cook(['FONTDIMEN',
         ['SLANT', 'R', 0], ['SPACE', 'R', 0],
         ['STRETCH', 'R', 0], ['SHRINK', 'R', 0],
         ['XHEIGHT', 'R', 0], ['QUAD', 'R', 0],
         ['EXTRASPACE', 'R', 0], ['EXTRASTRETCH', 'R', 0],
         ['EXTRASHRINK', 'R', 0]]);
  $q = $in->{quad}; (defined $q) or $q = 1;
  pl_set_real($pl->[6], 1, $q);
  $t = $in->{slant}; (defined $t) or $t = 0;
  pl_set_real($pl->[1], 1, $t);
  $t = $in->{space}; (defined $t) or $t = 0;
  pl_set_real($pl->[2], 1, $t);
  $t = $in->{stretch}; (defined $t) or $t = $q / 10;
  pl_set_real($pl->[3], 1, $t);
  $t = $in->{shrink}; (defined $t) or $t = 0;
  pl_set_real($pl->[4], 1, $t);
  $t = $in->{xheight}; (defined $t) or $t = $q;
  pl_set_real($pl->[5], 1, $t);
  $t = $in->{extraspace}; (defined $t) or $t = $q / 4;
  pl_set_real($pl->[7], 1, $t);
  $t = $in->{extrastretch}; (defined $t) or $t = $q / 5;
  pl_set_real($pl->[8], 1, $t);
  $t = $in->{extrashrink}; (defined $t) or $t = $q / 8;
  pl_set_real($pl->[9], 1, $t);
  return $pl;
}

# for pl_fonrdimen_?pl_rmt
our @pl_keys_quad_u_jpl = (
  0x4E00, 0x3042, 0x306E, 0xFF2D, 0x004D, 0x2014
);
our @pl_keys_quad_u_opl = (
  0x2001, 0x2003, 0x004D, 0x2014
);
our @pl_keys_space_u_opl = (
  0x0020, 0x00A0
);

##<*> pl_fontdimen_opl_rmt($rmt)
# Generates a FONTDIMEN list of OPL with values estimated from
# the glyph metric $rmt.
sub pl_fontdimen_opl_rmt
{
  my ($rmt) = @_; my ($t, $in);
  $in = { };
  (defined($t = pl_key_width($rmt, \@pl_keys_quad_u_opl)))
    and $in->{quad} = $t;
  (defined($t = pl_key_width($rmt, \@pl_keys_space_u_opl)))
    and $in->{space} = $t;
  return pl_fontdimen($in);
}

##<*> pl_fontdimen_jpl_rmt($rmt)
# Generates a FONTDIMEN list of JPL with values estimated from
# the glyph metric $rmt.
sub pl_fontdimen_jpl_rmt
{
  my ($rmt) = @_; my ($t, $in);
  $in = { };
  (defined($t = pl_key_width($rmt, \@pl_keys_quad_u_jpl)))
    and $in->{quad} = $t;
  return pl_fontdimen($in);
}

## pl_key_width($rmt)
# Subcontractor of pl_fontdimen_?pl_rmt.
sub pl_key_width
{
  my ($rmt, $keys) = @_; my ($t, %hsh);
  foreach (@$rmt) { $hsh{$_->[0]} = $_; }
  foreach (@$keys) {
    (defined($t = $hsh{$_})) or next;
    return $t->[1];
  }
  return;
}

## pl_cook($pl)
# Cooks a pl-list $pl and returns it. (Sometimes more convenient
# than pl_cook_list.)
*pl_cook = \&pl_cook_list;

# for pl_get_metric
my %pl_char_part_pos = (
  CHARWD => 1, CHARHT => 2, CHARDP => 3, CHARIC => 4
);

##<*> pl_get_metric($pl)
# Reads the metric data from the CHARACTER set of pl-struct $pl
# and converts them to a raw metric array.
sub pl_get_metric
{
  my ($pl) = @_; my ($t, $p, $pe, $pe2, $ent, @rmt);
  foreach $pe (@$pl) {
    if ($pe->[0] eq 'CHARACTER') {
      (defined($t = pl_value($pe, 1))) or return;
      $ent = [ $t ];
      foreach $pe2 (@{$pe}[3 .. $#$pe]) {
        if (defined($p = $pl_char_part_pos{$pe2->[0]})) {
          (defined($t = pl_value($pe2, 1))) or return;
          $ent->[$p] = $t / TU;
        }
      }
      push(@rmt, $ent);
    }
  }
  return \@rmt;
}

# for pl_char_part
my @pl_char_part_name = qw( * CHARWD CHARHT CHARDP CHARIC );

##<*> pl_char_part
# Converts a raw metric array to an array of CHARACTER lists.
# Partial inverse of pl_get_metric
sub pl_char_part
{
  my ($rmt) = @_; my ($ent, $pe, $pe2, $pl);
  $pl = [ ];
  foreach $ent (@$rmt) {
    $pe = pl_cook(['CHARACTER', 'C', 0]);
    pl_set_value($pe, 1, $ent->[0]);
    foreach (1 .. 4) {
      if (defined($ent->[$_])) {
        $pe2 = pl_cook([$pl_char_part_name[$_], 'R', 0]);
        pl_set_real($pe2, 1, $ent->[$_]); push(@$pe, $pe2);
      }
    }
    push(@$pl, $pe);
  }
  return $pl;
}

##<*> pl_char_part_jpl($imt, $vmt, $swu)
# ...
sub pl_char_part_jpl
{
  my ($imt, $vmt, $swu) = @_; my ($t, $cc, $ti, $jp);
  my (@cit, $pl, $pe, @u);
  $jp = ($swu) ? 'U' : 'J';
  foreach $cc (keys %$imt) {
    push(@{$cit[$imt->{$cc}]}, $cc);
  }
  foreach $ti (1 .. $#cit) {
    @u = map { sprintf("%s%04X", $jp, $_) }
             (sort { $a <=> $b } (@{$cit[$ti]}));
    $pe = pl_cook(['CHARSINTYPE', 'D', 0, @u]);
    pl_set_value($pe, 1, $ti); push(@$pl, $pe);
  }
  foreach $ti (0 .. $#$vmt) {
    $pe = pl_cook(['TYPE', 'D', 0, ['CHARWD', 'R', 0],
                   ['CHARHT', 'R', 0], ['CHARDP', 'R', 0]]);
    pl_set_value($pe, 1, $ti);
    pl_set_real($pe->[3], 1, $vmt->[$ti][0]);
    pl_set_real($pe->[4], 1, $vmt->[$ti][1]);
    pl_set_real($pe->[5], 1, $vmt->[$ti][2]);
    push(@$pl, $pe);
  }
  return $pl;
}


######## 'jcode' section ########

our $jcode_ex = K_JIS;
our $jcode_in = KI_JIS;
our $jfm_forced_prefix;

my %jcode_ex_sym = ( jis => K_JIS, euc => K_EUC,
                     sjis => K_SJIS, utf8 => K_UTF8,
                     none => undef, xjis => K_XJIS );
my %jcode_in_sym = ( jis => KI_JIS, unicode => KI_UNI,
                     none => undef, xjis => KI_XJIS );
  # 'xjis' is for internal use

##<*> jcode_set($xjc, $ijc)
# Declares external [internal] Japanese code to be $xjc [$ijc],
# which is a key of %jcode_ex_sym [%jcode_in_sym].
sub jcode_set
{
  my ($xjc, $ijc) = @_; my ($t);
  if (defined $xjc) {
    (exists $jcode_ex_sym{$xjc}) or return;
    $jcode_ex = $jcode_ex_sym{$xjc};
  }
  if (defined $ijc) {
    (exists $jcode_in_sym{$ijc}) or return;
    $jcode_in = $jcode_in_sym{$ijc};
  }
  #if (!defined $jcode_ex || !defined $jcode_in) {
  #  $jcode_ex = $jcode_in = undef;
  #}
  return 1;
}

##<*> jcode_chr($cod)
# Converts a code value of the internal code to a string containing
# the character encoded in the external code.
sub jcode_chr
{
  my ($cod) = @_; my ($xs, $is);
  (defined $jcode_in && defined $jcode_ex) or return;
  (0 <= $cod && $cod <= 0xFFFF) or return;
  $xs = chr($cod >> 8) . chr($cod & 0xFF);
  eval {
    $is = decode($jcode_in, $xs, Encode::FB_CROAK);
    $xs = encode($jcode_ex, $is, Encode::FB_CROAK);
  };
  ($@ eq '' && length($is) == 1) or return;
  return $xs;
}

##<*> jcode_ord($xs)
# Inverse of jcode_chr.
sub jcode_ord
{
  my ($xs) = @_; my ($is, $cod, $f);
  (defined $jcode_in && defined $jcode_ex) or return;
  if ($jcode_in eq KI_XJIS && $jcode_ex eq K_XJIS) {
    $xs =~ m/\x1B\x24\x42(..)\x1B\x28\x42/ or return;
    return unpack('n', $1);
  }
  eval {
    $is = decode($jcode_ex, $xs, Encode::FB_CROAK);
    (length($is) == 1) or die;
  };
  ($@ eq '') or return;
  if ($jcode_in eq KI_UNI) { return ord($is); }
  eval {
    $xs = encode($jcode_in, $is, Encode::FB_CROAK);
  };
  ($@ eq '' && $xs =~ m/^(.)(.)$/s) or return;
  return (ord($1) << 8 | ord($2));
}

######## 'ps' section ########

#### ps_parse0: shallow parser
# The 'shallow parser' converts a whole PS text into a list of
# (pseudo)tokens (each of which is a simple scalar value):
# where '[', ']', '<<', '>>' are treated as a separate token
# and represented as strings read as itself; and other tokens
# are represented as follows.
#   number:   +123.0     -> number 123
#   operator: abc        -> string _abc
#   name:     /abc       -> string /abc
#   literal   (abc)      -> string 'abc
#   hexstring <616263>   -> string "abc

sub ps_parse0
{
  my ($txt) = @_; my ($p, $tok, @toks);
  while ($txt =~ m/\G((\s+)|<<|>>|(\%)|(<)|(\()| #)
                      (\/?[^<>()\/\[\]\{\}\%\s]+)|.)/gx) {
    $p = pos($txt);
    if (defined $2) { next; } # spaces
    elsif (defined $3) { # '% comment'
      $txt =~ m/\G.*$/gm; next;
    } elsif (defined $4) { # <hexstring>
      ($tok, pos($txt)) = ps_parse0_hexstr($txt, $p);
      (defined $tok) or return ps_parse0_error($txt, $p - 1);
    } elsif (defined $5) { # (literalstring)
      ($tok, pos($txt)) = ps_parse0_litstr($txt, $p);
      (defined $tok) or return ps_parse0_error($txt, $p - 1);
    } elsif (defined $6) {
      $tok = $6;
      if ($tok =~ m/^[+-]?\d+(?:\.\d*)?$/) { $tok += 0; }
      elsif ($tok !~ m|^/|) { $tok = "_$tok"; }
    } else { $tok = $1; }
    push(@toks, $tok);
  }
  return \@toks;
}
sub ps_parse0_hexstr
{
  my ($txt, $p) = @_; my ($t);
  pos($txt) = $p; $txt =~ m/([\d\sA-Fa-f]*)/g; $t = $1;
  ($txt =~ m/\G>/g) or return;
  $t =~ s/\s+//g; $t = pack("H*", $t);
  return ("\"$t", pos($txt));
}
sub ps_parse0_litstr
{
  my ($txt, $p) = @_; my ($t);
  pos($txt) = $p;
  ($txt =~ m/(.*?)\)/gs) or return; $t = $1;
  return ("\'$t", pos($txt));
}

sub ps_s { return substr($_[0], 1); }
sub ps_form
{
  my ($tok) = @_;
  return ($tok =~ m/^[\"\']/) ? "<str>" :
         ($tok =~ m/^_/) ? ps_s($tok) : $tok;
}


sub ps_parse0_error
{
  my ($txt, $p) = @_; my ($t);
  $t = substr($txt, $p, 10);
  return error("syntax error in PS code (near $t...)");
}

######## 'enc' section ########

# The data structure for encoding vectors is merely an array ref
# of glyph names. Usually this array has 256 elements but can be
# otherwise. The name '.notdef' is represented as undef.
# In addition, this module provides a registry of encodings, which
# is a hash that maps an enc name to an enc array.

##<*> enc_parse($txt)
# Converts a text $txt in the form of '.enc' files to an enc array.
# In list context it returns ($key, $enc) where $key is the name of
# encoding and $enc is the array, while in scalar context it returns
# $enc only.
sub enc_parse
{
  my ($txt, $sw) = @_; my ($dat, $key, @enc);
  L1:{
    (defined($dat = ps_parse0($txt))) or last;
    ($dat->[1] eq '[' && $dat->[-2] eq ']' && $dat->[-1] eq '_def' &&
     $dat->[0] =~ m|^/(.*)|) or last;
    $key = $1;
    foreach (2 .. $#$dat - 2) {
      ($dat->[$_] =~ m|^/(.*)|) or last L1;
      push(@enc, ($1 eq '.notdef' && !$sw) ? undef : $1);
    }
    enc_register($key, \@enc);
    return (wantarray) ? ($key, \@enc) : \@enc;
  }
  return error("syntax error in enc data");
}

# for enc_form
use constant {
  ENCF_NORMAL => 0, ENCF_ANNOT => 1, ENCF_COMPACT => 2,
  ENCF_256 => 256
};
our $enc_form_indwd = 2;     # indent width
our $enc_form_annwd = 24;    # column where comments stay
our $enc_form_linwd = 72;    # maximum line length

##<*> enc_form($key, $enc, $mod)
# Converts enc array $enc to the text of .enc file. Here $key is
# the name the encoding vector will be defined with, and $mod
# specifies the output form and is OR-value of the following:
#   ENCF_NORMAL:     normal, one line per name
#   ENCF_ANNOT:      with comment like "% 0x18" per 8 lines
#   ENCF_COMPACT:    crams to a line as many names as possible
#   ENCF_256:        see as if the array has 256 entries
# If $enc is undef, array registered by name $key is used.
sub enc_form
{
  my ($key, $enc, $mod) = @_;
  my ($swsl, $k, $t, $l, $s, @lins, @enx);
  if (ref $enc ne 'ARRAY') {
    $mod = $enc;
    (defined($enc = enc_retrieve($key)))
      or return error("unknown enc name: $key");
  }
  $l = ($mod & 256) ? 255 : $#$enc; $mod = $mod & 15;
  foreach $k (0 .. $l) {
    $t = $enc->[$k]; $enx[$k] = (defined $t) ? "/$t" : '/.notdef';
  }
  @lins = ("/$key ["); $s = ' ' x $enc_form_indwd;
  if ($mod == ENCF_NORMAL) {
    foreach $k (@enx) { push(@lins, "$s$k"); }
  } elsif ($mod == ENCF_ANNOT) {
    foreach $k (0 .. $#enx) {
      $t = "$s" . $enx[$k];
      if ($k % 8 == 0) {
        $l = $enc_form_annwd - length($t); if ($l < 1) { $l = 1; }
        $t .= sprintf("%s%% 0x%02X", ' ' x $l, $k);
      }
      push(@lins, $t);
    }
  } elsif ($mod == ENCF_COMPACT) {
    $t = '';
    foreach $k (@enx) {
      if ($t eq '') { $t = $k; }
      elsif (length($t) + length($k) + 1 > $enc_form_linwd) {
        push(@lins, $t); $t = $k;
      } else { $t .= " $k"; }
    }
    push(@lins, $t);
  } else { return error("invalid mode given: $mod"); }
  push(@lins, "] def", '');
  return join("\n", @lins);
}

#### Procedures for the encoding registry

our %enc_registry;

##<*> enc_register($key, $enc)
# Register enc array $enc for name $key. If $enc is undef, then
# the entry for $key is deleted.
sub enc_register
{
  my ($key, $enc) = @_;
  if (defined $enc) { $enc_registry{$key} = $enc; }
  else { delete $enc_registry{$key}; }
}

##<*> enc_retrieve($key)
# Returns the enc array registered by name $key.
sub enc_retrieve
{
  return $enc_registry{$_[0]};
}

##<*> enc($key, $c)
# Returns the glyph name of code $c in the enc array registered
# by name $key.
sub enc
{
  return $enc_registry{$_[0]}[$_[1]];
}

######## 'kpse' section ########

our $kpse_init_done;
our $kpse_delim;
our %kpse_format_alias = (
  cmap => 'cmap files',
);

##<*> kpse($fnam, $opt)
# Executes 'kpsewhich' for filename $fnam with option $opt.
# If $opt is a scalar, it means the value for 'format' option.
# If $opt is a hash ref, then the value for keys 'dpi', 'engine',
# 'mode', 'progname' and 'format' corresponds with the value of the
# option with same name and the boolean value for key 'mustexist'
# corresponds with existence of 'must-exist' option. For 'option'
# value, aliasing specified with %kpse_format_alias is done.
sub kpse
{
  my ($fnam, $opt) = @_; my ($cmd, $res);
  ($kpse_init_done || kpse_init()) or return undef;
  $opt = kpse_parse_option($opt, $fnam); $cmd = $cmd_name{kpsewhich};
  if (ref $opt eq 'ARRAY') { return kpse_manual($fnam, $opt); }
  $res = `$cmd $opt "$fnam"`; chomp($res);
  if (-f $res) { return $res; }
  else {                            # returns undef, not nothing
    error("kpse failed to find a file: $fnam"); return undef;
  }
}

##<*> kpse_init()
# Initializes the kpse section of this module.
sub kpse_init
{
  my ($res, $cmd);
  (!defined $kpse_init_done)
    or return error("kpsewhich failure");
  $cmd = $cmd_name{kpsewhich};
  if (($res = `$cmd -show-path=tex`) eq '') {
    $kpse_init_done = 0;
    return error("kpsewhich failure");
  }
  if ($res =~ m/^\.\:/) { $kpse_delim = ':'; }
  elsif ($res =~ m/;/) { $kpse_delim = ';'; }
  else { $kpse_delim = ':'; }
  $kpse_init_done = 1;
  return 1;
}

## kpse_parse_option($opt)
# Subcontractor of kpse.
sub kpse_parse_option
{
  my ($opt, $fnam) = @_; my ($o, $t, @copts);
  if (ref $opt eq 'ARRAY') { return $opt; } # for future extension
  elsif (ref $opt eq 'HASH') {
    foreach $o (qw(dpi engine mode progname)) {
      if (exists $opt->{$o}) {
        push(@copts, "-$o=" . $opt->{$o});
      }
    }
    if ($opt->{mustexist}) { push(@copts, '-must-exist'); }
    $opt = $opt->{format};
  }
  if ($opt eq '' && $fnam =~ m/\.vf$/i) { $opt = "vf"; }
  if ($opt ne '') {
    if (defined($t = $kpse_format_alias{$opt})) { $opt = $t; }
    push(@copts, "-format=\"$opt\"");
  }
  return join(' ', @copts);
}

######## 'ttf' section ########

# * Data structure: raw metric
# A raw metric struct holds the most basic metric data of a font and
# is formed as follows: a raw metric is an array ref of character
# metric entries, which are of the following form:
#  [ <code>, <width>, <height>, <depth> ]
# here the unit of length is the designated size.

##<*> ttf_generate_opl($ffnt, $id)
# Read the metric of a TTF file $ffnt (in case of TTC index is given
# by $id) and generates the pl-struct describing ofm for the metric.
sub ttf_generate_opl
{
  my ($ffnt, $id) = @_; my ($t, $rmt, $fd, $pl, $chp);
  ($t = $ffnt) =~ s|.*/(.*)|$1|;
  $t = { family => $t, codingscheme => 'UNICODE' };
  (defined($rmt = ttf_get_metric($ffnt, $id)) &&
   defined($fd = pl_fontdimen_opl_rmt($rmt)) &&
   defined($pl = pl_header_opl($t, $fd, 0)) &&
   defined($chp = pl_char_part($rmt))) or return;
  push(@$pl, @$chp);
  return $pl;
}

# for ttf_get_metric
  # This table designates the procedure to get raw metric of
  # a given type (known by extension) of font file.
our %ttf_get_metric_proc = (
 #ttf => \&ttf_get_metric_ttf2tfm,
  ttf => \&ttf_get_metric_xetex,
  otf => \&ttf_get_metric_xetex,
);

##<*> ttf_get_metric($fnam, $id)
sub ttf_get_metric
{
  my ($ffnt, $id) = @_; my ($rmt, $prc);
  L1:{
    if ($ffnt =~ m/\.ttf$/i) {
      $prc = $ttf_get_metric_proc{ttf};
      (defined($rmt = &$prc($ffnt))) or last L1;
    } elsif ($ffnt =~ m/\.ttc$/i) {
      $prc = $ttf_get_metric_proc{ttf};
      (defined($rmt = &$prc($ffnt, $id))) or last L1;
    } elsif ($ffnt =~ m/\.(\w{3,4})$/i) {
      $prc = $ttf_get_metric_proc{lc($1)};
      (defined($rmt = &$prc($ffnt, $id))) or last L1;
    } else { last L1; }
    return $rmt;
  }
  return error("failed to get font metric: $ffnt");
}

## ttf_get_metric_ttf2tfm($fnam, $id)
sub ttf_get_metric_ttf2tfm
{
  my ($ffnt, $id) = @_; my ($t, $tb, $cout, $rmt, @tfms);
  $tb = get_temp_name();
  @tfms = map { sprintf("%s-%02x.tfm", $tb, $_) } (0 .. 255);
  unlink(@tfms);
  $t = (defined $id) ? "-f $id" : '';
  $cout = `ttf2tfm "$ffnt" $t $tb-\@Unicode\@`;
  (unlink(@tfms) > 0) or return;
  return ttf_parse_out_ttf2tfm($cout);
}

# for ttf_parse_out_ttf2tfm
our $ttf_ttf2tfm_scale = 1000;
  # Is that always 1000?

## ttf_parse_out_ttf2tfm(...)
# Subcontractor of ttf_get_metric_ttf2tfm.
sub ttf_parse_out_ttf2tfm
{
  my ($txt) = @_; my ($scl, $lin, $stg, @fs, @rmt);
  $scl = $ttf_ttf2tfm_scale;
  foreach $lin (split(/\n/, $txt)) {
    if ($lin eq '') { $stg = 0; }
    elsif ($stg == 0 && $lin =~ m/^\s*Glyph/) { $stg = 1; }
    elsif ($stg == 1 && $lin =~ m/^\s*-----/) { $stg = 2; }
    elsif ($stg == 2 && (@fs = $lin =~
            m/^\s*(\d+)\s+(\w+)\s+(\S+)\s+(-?\d+)
              \s+(-?\d+),\s*(-?\d+)\s*--\s*(-?\d+),\s*(-?\d+)/x)) {
      push(@rmt, [ hex($fs[1]), $fs[3] / $scl, $fs[7] / $scl,
                   -$fs[5] / $scl ]);
    }
  }
  return \@rmt;
}

## ttf_get_metric_xetex(...)
# Dispatcher of ttf_get_metric for OpenType fonts.
sub ttf_get_metric_xetex
{
  my ($ffnt) = @_; my ($t, $ftb, $cout);
  $ftb = get_temp_name();
  $t = <<"END1" . <<'END2';
\\def\\fn{$ffnt}
END1
\newcount\cc \newbox\cb
\font\fs="[\fn]"\relax\fs
\immediate\write-1{>>>Start}%
\cc=0 \loop \ifnum\XeTeXcharglyph\cc>0
    \setbox\cb\hbox{\char\cc}%
    \immediate\write-1{>>\the\cc/\the\wd\cb/\the\ht\cb/\the\dp\cb}%
  \fi
\advance\cc1 \ifnum\cc<"10000 \repeat
\immediate\write-1{>>>End}%
\bye
END2
  (write_whole_file("$ftb.tex", $t)) or return;
  $cout = `xetex -halt-on-error -no-pdf $ftb`;
  (defined($t = read_whole_file("$ftb.log"))) or return;
  unlink("$ftb.tex", "$ftb.log", "$ftb.xdv");
  return ttf_parse_out_xetex($t);
}

## ttf_parse_out_xetex(...)
# Subcontractor of ttf_get_metric_xetex.
sub ttf_parse_out_xetex
{
  my ($txt) = @_; my ($stg, $lin, @fs, @rmt);
  $stg = 0;
  foreach $lin (split(/\n/, $txt)) {
    if ($stg == 0) {
      if ($lin eq '>>>Start') { $stg = 1; }
    } elsif ($stg == 1) {
      if (@fs = $lin =~
          m|^>>(\d+)/(-?[\.\d]+)pt/(-?[\.\d]+)pt/(-?[\.\d]+)pt$|) {
        push(@rmt, [ $fs[0], map { sprintf("%.5f", $_ / 10) - 0 }
                                 (@fs[1, 2, 3]) ]);
      } elsif ($lin eq '>>>End') { $stg = 2; }
      else { last; }
    } else { last; }
  }
  if ($stg != 2) { return; }
  return \@rmt;
}

######## 'tfm' section ########

##<*> tfm_reduce_jpl($rmt, $d)
# Constructs a JFM metric, making the best effort to minimize the
# maximum height/depth error under the condition the maximum width
# error must be at most $d.
sub tfm_reduce_jpl
{
  my ($rmt, $dw) = @_; my ($imt, $vmt, $d, $dl, $dh);
  ($imt, $vmt) = tfm_try_reduce_jpl($rmt, $dw, 0);
  if (defined $vmt) { return (0, $imt, $vmt); }
  for ($d = 1; $d <= 2048; $d *= 2) {
    ($imt, $vmt) = tfm_try_reduce_jpl($rmt, $dw, $d);
    if (defined $vmt) { last; }
  }
  ($d <= 2048) or return;
  $dl = 0; $dh = $d;
  while ($dh - $dl > 9e-7) {  # 9e-7 < 2**-20
    $d = ($dl + $dh) / 2;
    ($imt, $vmt) = tfm_try_reduce_jpl($rmt, $dw, $d);
    if (defined $vmt) { $dh = $d; }
    else { $dl = $d; }
  }
  $d = $dh; ($imt, $vmt) = tfm_try_reduce_jpl($rmt, $dw, $d);
  (defined $vmt) or return fatal("tfm_reduce_jpl_x");
  return ($dw, $d, $imt, $vmt);
}

##<*> tfm_reduce_jpl_x($rmt, $bf)
# Constructs a JFM metric, making the best effort to minimize the
# value d that satisfies the condition the maximum error of width,
# height, and depth must be at most d/$bf, d, and d.
sub tfm_reduce_jpl_x
{
  my ($rmt, $bf) = @_; my ($imt, $vmt, $d, $dl, $dh);
  if (!defined $bf) { $bf = 20; }
  ($imt, $vmt) = tfm_try_reduce_jpl($rmt, 0, 0);
  if (defined $vmt) { return (0, $imt, $vmt); }
  for ($d = 1; $d <= 2048; $d *= 2) {
    ($imt, $vmt) = tfm_try_reduce_jpl($rmt, $d / $bf, $d);
    if (defined $vmt) { last; }
  }
  ($d <= 2048) or return;
  $dl = 0; $dh = $d;
  while ($dh - $dl > 1e-7) {
    $d = ($dl + $dh) / 2;
    ($imt, $vmt) = tfm_try_reduce_jpl($rmt, $d / $bf, $d);
    if (defined $vmt) { $dh = $d; }
    else { $dl = $d; }
  }
  $d = $dh; ($imt, $vmt) = tfm_try_reduce_jpl($rmt, $d / $bf, $d);
  (defined $vmt) or return fatal("tfm_reduce_jpl_x");
  return ($d / $bf, $d, $imt, $vmt);
}

## tfm_try_reduce_jpl($rmt, $d1, $d2)
# Subcontractor of tfm_reduce_jpl_x. (Here $d1 is the error limit of
# widths and $d2 is of heights and depths.
sub tfm_try_reduce_jpl
{
  my ($rmt,  $d1, $d2) = @_; my ($j, $t, $e, @u, %cnt);
  my (@ovs, @is, @vs, %imt, @vmt);
  @u = ([], [$d1, 0], [$d2, 1], [$d2, 1]);
  foreach $t (1 .. 3) {
    @{$ovs[$t]} = map { $_->[$t] } (@$rmt);
    ($is[$t], $vs[$t]) = tfm_set_indices_j($ovs[$t], @{$u[$t]});
    (scalar(@{$vs[$t]}) <= 256) or return;
  }
  foreach $j (0 .. $#$rmt) {
    @u = map { pl_form_real($vs[$_][$is[$_][$j]]) } (1 .. 3);
    $imt{$rmt->[$j][0]} = $t = join('/', @u); $cnt{$t} += 1;
  }
  @vmt = keys %cnt; (scalar(@vmt) <= 256) or return;
  @vmt = sort { $cnt{$b} <=> $cnt{$a} } (@vmt);
  foreach (0 .. $#vmt) { $cnt{$vmt[$_]} = $_; }
  foreach (keys %imt) {  $imt{$_} = $cnt{$imt{$_}}; }
  @vmt = map { [split(m|/|, $_)] } (@vmt);
  return (\%imt, \@vmt);
}

###<*> tfm_reduce($rmt)
sub tfm_reduce
{
  my ($rmt) = @_; my ($t, $e, %cnt);
  my (@wds, @hts, @dps, $iht, $vht, $idp, $vdp, %imt, @vmt);
  (@$rmt) or return error("metric data are empty");
  @wds = map { $_->[1] } (@$rmt);
  (($t = tfm_count_kind(\@wds)) <= 255)
    or return error("too many kinds ($t > 255) of widths");
  @hts = map { $_->[2] } (@$rmt);
  ($iht, $vht) = tfm_set_indices(\@hts, 16);
  @dps = map { $_->[3] } (@$rmt);
  ($idp, $vdp) = tfm_set_indices(\@dps, 16);
  foreach $e (@$rmt) {
    $t = join('/', $e->[1], $vht->[$iht->[$e->[2]]],
                   $vdp->[$idp->[$e->[3]]]);
    $imt{$e->[0]} = $t; $cnt{$t} += 1;
  }
  @vmt = sort { $cnt{$b} <=> $cnt{$a} } (keys %cnt);
  foreach (0 .. $#vmt) { $cnt{$vmt[$_]} = $_; }
  foreach (keys %imt) {  $imt{$_} = $cnt{$imt{$_}}; }
  foreach $t (0 .. $#vmt) {
    $vmt[$t] = [ (split(m|/|, $vmt[$t])) ];
  }
  return (\%imt, \@vmt);
}

## tfm_count_kind($ary)
# Returns the number of distinct elements in an array $ary.
sub tfm_count_kind
{
  my ($ary) = @_; my (%hsh, @a2);
  foreach (@$ary) { $hsh{$_} += 1; }
  @a2 = keys %hsh; return scalar(@a2);
}

## tfm_set_indices($ary, $m)
# Reduces a set $ary of reals to ($m - 1) elements using the
# same rounding algorithm as in pltotf (here $m is decremented
# because zero comes into the list later). It returns ($idx, $val)
# where $val is the reduced set and $idx is the index array
# for the original array $ary.
sub tfm_set_indices
{
  my ($ary, $m) = @_; my ($v, $v1, $d, @ary2, @idx, @val, %hsh);
  foreach $v (@$ary) { $hsh{$v} = 1; }
  delete $hsh{0}; @ary2 = sort { $a <=> $b } (keys %hsh);
  --$m; $d = tfm_shorten(\@ary2, $m);
  @val = (0); %hsh = (0, 0); $m = 0; $v1 = -2 * HUGE;
  foreach $v (@ary2) {
    if ($v > $v1 + $d) {
      $hsh{$v} = ++$m; $val[$m] = $v1 = $v;
    } else {
      $val[$m] = ($v1 + $v) / 2; $hsh{$v} = $m;
    }
  }
  @idx = map { $hsh{$_} } (@$ary);
  return (\@idx, \@val, $d);
}

## tfm_set_indices_j($ary, $d, $sw)
# Similar as tfm_set_indices, but here $d is the maximum permitted
# value of round error. If $sw is 0/1/2 ,then values in a range
# is rounded to mid-value/lower-limit/upper-limit of the range.
sub tfm_set_indices_j
{
  my ($ary, $d, $sw) = @_;
  my ($v, $v1, $m, @ary2, @idx, @val, %hsh);
  foreach $v (@$ary) { $hsh{$v} = 1; }
  delete $hsh{0}; @ary2 = sort { $a <=> $b } (keys %hsh);
  @val = (0); %hsh = (0, 0); $m = 0; $v1 = -2 * HUGE;
  foreach $v (@ary2) {
    if ($v > $v1 + $d) {
      $hsh{$v} = ++$m; $val[$m] = $v1 = $v;
    } else {
      $val[$m] = ($sw == 1) ? $v1 : ($sw == 2) ? $v :
                 (($v1 + $v) / 2);
      $hsh{$v} = $m;
    }
  }
  @idx = map { $hsh{$_} } (@$ary);
  return (\@idx, \@val);
}

## tfm_min_cover($ary, $d)
# Subcontractor of tfm_indices.
sub tfm_min_cover
{
  my ($ary, $d) = @_; my ($v, $d1, $v1, $dnxt, $m);
  $m = 0; $dnxt = HUGE; $v1 = -2 * HUGE;
  foreach $v (@$ary) {
    if ($v > $v1 + $d) {
      $d1 = $v - $v1; $v1 = $v; ++$m;
      if ($d1 < $dnxt) { $dnxt = $d1; }
    }
  }
  return ($m, $dnxt);
}

## tfm_shorten($ary, $m)
# Subcontractor of tfm_indices.
sub tfm_shorten
{
  my ($ary, $m) = @_; my ($k, $d, $d1);
  ($k, $d) = tfm_min_cover($ary, 0);
  if ($k <= $m) { return 0; }
  while ($k > $m) { $d += $d; ($k) = tfm_min_cover($ary, $d); }
  $d /= 2; ($k, $d1) = tfm_min_cover($ary, $d);
  while ($k > $m) { $d = $d1; ($k, $d1) = tfm_min_cover($ary, $d); }
  return $d;
}

##<*> tfm_reduced_metric($imt, $vmt)
sub tfm_reduced_metric
{
  my ($imt, $vmt) = @_; my ($cc, @ccs, $t, @rmt);
  @ccs = sort { $a <=> $b } (keys %$imt);
  foreach $cc (@ccs) {
    $t = $vmt->[$imt->{$cc}];
    push(@rmt, [$cc, @$t]);
  }
  return \@rmt;
}

##<*> tfm_map_rmt($rmt, $map)
# Remaps the character code used in a raw metric $rmt by applying
# $map backwards.
sub tfm_map_rmt
{
  my ($rmt, $map) = @_; my ($e, $t, @rmt2, %hsh);
  (defined($map = arraymap($map))) or return;
  foreach (@$rmt) { $hsh{$_->[0]} = $_; }
  foreach $e (@$map) {
    (defined($t = $hsh{$e->[1]})) or next;
    push(@rmt2, [$e->[0], @{$t}[1 .. $#$t]]);
  }
  return \@rmt2;
}


######## 'vf' section ########

##<*> vf_strict($sw)
# Sets strict mode in parsing or forming VF.
our $vf_strict = 1;
sub vf_strict { $vf_strict = $_[0]; }

## vf_simple_move_code($sw)
# Sets the value of $vf_simple_move_code. If it is true, then
# vf_form does not exploit w, x, y, z registers in compiling
# move operations in DVI code.
our $vf_simple_move_code = 0;
sub vf_simple_move_code { $vf_simple_move_code = $_[0]; }

##-------- Procedures on ZVP0 format

##<*> vf_parse($dat, $swdh)
# Converts a (binary) VF data $dat to a pl-struct describing
# ZPL0 data. If something invalid is found in DVI code and $swdh
# is true, then DVI is written with a DIRECTHEX entry.
sub vf_parse
{
  my ($dat, $swdh) = @_;
  my ($t, $u, @fs, $pos, $pl, $pe, $stg);
  (defined $swdh) or $swdh = !$vf_strict;
  (length($dat) >= 3) or return vf_synerror("in preamble");
  @fs = unpack("CCC/a*NN", $dat); $pos = length($fs[2]) + 11;
  ($#fs == 4 && $fs[0] == 247 && $fs[1] == 202)
    or return vf_synerror("in preamble");
  $pl = pl_header_vpl({ vtitle => $fs[2], checksum => $fs[3],
                        designsize => $fs[4] / TU });
  for (;;) {
    $t = ord(substr($dat, $pos, 1));
    if ($stg <= 2 && 0 <= $t && $t <= 241) { # short_charN
      @fs = unpack("CCa3a$t", substr($dat, $pos, $t + 5)); $pos += $t + 5;
      ($#fs == 3 && length($fs[3]) == $t)
        or return vf_synerror("premature end");
      $pe = pl_cook(['CHARACTER', 'C', 0,
                     ['CHARWD', 'R', 0], undef]);
      if (defined($t = vf_dvi_parse($fs[3]))) { $pe->[4] = $t; }
      elsif (!$swdh) {
        return vf_synerror("illegal dvi code (char $fs[1])");
      } else { $pe->[4] = vf_dvi_dumb_parse($u); }
      pl_set_value($pe->[3], 1, unpack_num($fs[2])); # (unsigned)
      pl_set_value($pe, 1, $fs[1]);
      $stg = 2; push(@$pl, $pe);
    } elsif ($stg <= 2 && $t == 242) { # long_char
      @fs = unpack("CNNN", substr($dat, $pos, 13)); $pos += 13;
      $u = substr($dat, $pos, $fs[1]); $pos += $fs[1];
      #-- give a cooked list for efficiency
      #$pe = pl_cook(['CHARACTER', 'C', 0,
      #               ['CHARWD', 'R', 0], undef]);
      $pe = (['CHARACTER', [CNUM, 0, 'C'], 0,
              ['CHARWD', [CNUM, 0, 'R'], 0], undef]);
      if (defined($t = vf_dvi_parse($u))) { $pe->[4] = $t; }
      elsif (!$swdh) {
        return vf_synerror("illegal dvi code (char $fs[2])");
      } else { $pe->[4] = vf_dvi_dumb_parse($u); }
      pl_set_value($pe->[3], 1, signed($fs[3]));
      pl_set_value($pe, 1, $fs[2]);
      $stg = 2; push(@$pl, $pe);
    } elsif ($stg <= 1 && 243 <= $t && $t <= 246) { # fnt_defN
      $t -= 242;
      @fs = unpack("Ca${t}NNNCC", substr($dat, $pos, $t + 15)); $pos += $t + 15;
      ($#fs == 6) or return vf_synerror("premature end");;
      $t = $fs[5] + $fs[6]; $u = substr($dat, $pos, $t); $pos += $t;
      (length($u) == $t) or return vf_synerror("premature end");;
      $fs[6] = substr($u, $fs[5]); $fs[5] = substr($u, 0, $fs[5]);
      $pe = pl_cook(['MAPFONT', 'D', 0, ['FONTAREA', 0],
                     ['FONTNAME', 0],, ['FONTCHECKSUM', 'O', 0],
                     ['FONTAT', 'R', 0], ['FONTDSIZE', 'R', 0]]);
      $pe->[3][1] = $fs[5]; $pe->[4][1] = $fs[6];
      pl_set_value($pe->[5], 1, $fs[2]);
      pl_set_value($pe->[6], 1, $fs[3]);
      pl_set_value($pe->[7], 1, $fs[4]);
      pl_set_value($pe, 1, unpack_num($fs[1]));
      if ($fs[5] eq '') { splice(@$pe, 3, 1); }
      $stg = 1; push(@$pl, $pe);
    } elsif ($stg <= 2 && $t == 248) { # post
      (($u = substr($dat, $pos, $t)) =~ /^\xf8+$/)
        or return vf_synerror("in postamble");
      $stg = 3;
      last;
    } else { return vf_synerror("unexpected byte $t"); }
  }
  ($swdh || $stg == 3) or return vf_synerror("premature end");
  return $pl;
}

## vf_dvi_parse($dat)
# Subcontractor of vf_parse.
sub vf_dvi_parse
{
  my ($dat) = @_;
  my ($t, $u, @fs, $pos, $pl, $pe, $stk, $stg);
  $pl = ['MAP']; $stk = [{}];
  for ($pos = 0; $pos < length($dat); ) {
    $t = ord(substr($dat, $pos, 1));
    if (0 <= $t && $t <= 127) { # set_charN
      $pe = pl_cook(['SETCHAR', 'C', 0]); $pos += 1;
      pl_set_value($pe, 1, $t); push(@$pl, $pe);
    } elsif (128 <= $t && $t <= 131) { # setN
      $t -= 127; @fs = unpack("Ca$t", substr($dat, $pos));
      $pos += $t + 1; ($#fs == 1) or return;
      $pe = pl_cook(['SETCHAR', 'C', 0]);
      pl_set_value($pe, 1, unpack_num($fs[1])); push(@$pl, $pe);
    } elsif ($t == 132) { # setrule
      @fs = unpack("CNN", substr($dat, $pos));
      $pos += 9; ($#fs == 2) or return;
      $pe = pl_cook(['SETRULE', 'R', 0, 'R', 0]);
      pl_set_value($pe, 1, signed($fs[1]));
      pl_set_value($pe, 3, signed($fs[2])); push(@$pl, $pe);
    } elsif ($t == 141) { # push
      $pos += 1; push(@$pl, ['PUSH']); push(@$stk, {});
    } elsif ($t == 142) { # pop
      $pos += 1; push(@$pl, ['POP']); pop(@$stk);
      (@$stk) or return;
    } elsif (143 <= $t && $t <= 146) { # rightN
      ($pe, $pos) = vf_dvi_move1($dat, $pos, $stk, 'r', $t - 142);
      (defined $pe) or return; push(@$pl, $pe);
    } elsif ($t == 147) { # w0
      ($pe, $pos) = vf_dvi_move0($dat, $pos, $stk, 'w');
      (defined $pe) or return; push(@$pl, $pe);
    } elsif (148 <= $t && $t <= 151) { # wN
      ($pe, $pos) = vf_dvi_move1($dat, $pos, $stk, 'w', $t - 147);
      (defined $pe) or return; push(@$pl, $pe);
    } elsif ($t == 152) { # x0
      ($pe, $pos) = vf_dvi_move0($dat, $pos, $stk, 'x');
      (defined $pe) or return; push(@$pl, $pe);
    } elsif (153 <= $t && $t <= 156) { # xN
      ($pe, $pos) = vf_dvi_move1($dat, $pos, $stk, 'x', $t - 152);
      (defined $pe) or return; push(@$pl, $pe);
    } elsif (157 <= $t && $t <= 160) { # downN
      ($pe, $pos) = vf_dvi_move1($dat, $pos, $stk, 'd', $t - 156);
      (defined $pe) or return; push(@$pl, $pe);
    } elsif ($t == 161) { # y0
      ($pe, $pos) = vf_dvi_move0($dat, $pos, $stk, 'y');
      (defined $pe) or return; push(@$pl, $pe);
    } elsif (162 <= $t && $t <= 165) { # yN
      ($pe, $pos) = vf_dvi_move1($dat, $pos, $stk, 'y', $t - 161);
      (defined $pe) or return; push(@$pl, $pe);
    } elsif ($t == 166) { # z0
      ($pe, $pos) = vf_dvi_move0($dat, $pos, $stk, 'z');
      (defined $pe) or return; push(@$pl, $pe);
    } elsif (167 <= $t && $t <= 170) { # zN
      ($pe, $pos) = vf_dvi_move1($dat, $pos, $stk, 'z', $t - 166);
      (defined $pe) or return; push(@$pl, $pe);
    } elsif (171 <= $t && $t <= 234) { # fnt_numN
      $t -= 171; $pe = pl_cook(['SELECTFONT', 'D', 0]); $pos += 1;
      pl_set_value($pe, 1, $t); push(@$pl, $pe);
    } elsif (235 <= $t && $t <= 238) { # fntN
      $t -= 234; @fs = unpack("Ca$t", substr($dat, $pos));
      $pos += $t + 1; ($#fs == 1) or return;
      $pe = pl_cook(['SELECTFONT', 'D', 0]);
      pl_set_value($pe, 1, unpack_num($fs[1])); push(@$pl, $pe);
    } elsif (239 <= $t && $t <= 242) { # xxxN
      $t -= 238; @fs = unpack("Ca$t", substr($dat, $pos));
      $pos += $t + 1; ($#fs == 1) or return;
      $t = unpack_num($fs[1]); $u = substr($dat, $pos, $t);
      $pos += $t; ($t == length($u)) or return;
      $pe = vf_dvi_special($u); push(@$pl, $pe);
    } elsif ($t == 255) { # dir (JVF)
      @fs = unpack("CC", substr($dat, $pos));
      $pos += 2; ($#fs == 1) or return;
      $pe = pl_cook(['DIR', 'D', 0]);
      pl_set_value($pe, 1, $fs[1]); push(@$pl, $pe);
    } else { return; }
  }
  return $pl;
}

## vf_synerror($msg)
# Error messages in vf_parse.
sub vf_synerror
{
  return error("VF syntax error: $_[0]");
}

# for vf_dvi_move1 / vf_dvi_move0
my %vf_dvi_move = (
  r => 'MOVERIGHT', w => 'MOVERIGHT', x => 'MOVERIGHT',
  d => 'MOVEDOWN', y => 'MOVEDOWN', z => 'MOVEDOWN',
);

## vf_dvi_move1(...)
# Subcontractor of vf_dvi_parse.
sub vf_dvi_move1
{
  my ($dat, $pos, $stk, $r, $l) = @_; my ($t, $pe, @fs);
  @fs = unpack("Ca$l", substr($dat, $pos));
  $pos += $l + 1; ($#fs == 1) or return;
  $stk->[-1]{$r} = $t = unpack_snum($fs[1]);
  $pe = pl_cook([$vf_dvi_move{$r}, 'R', 0]);
  pl_set_value($pe, 1, $t);
  return ($pe, $pos);
}

## vf_dvi_move0(...)
# Subcontractor of vf_dvi_parse.
sub vf_dvi_move0
{
  my ($dat, $pos, $stk, $r) = @_; my ($t, $pe);
  (defined($t = $stk->[-1]{$r})) or return;
  $pe = pl_cook([$vf_dvi_move{$r}, 'R', 0]);
  pl_set_value($pe, 1, $t);
  return ($pe, $pos + 1);
}

## vf_dvi_special($dat)
# Subcontractor of vf_dvi_parse.
sub vf_dvi_special
{
  my ($dat) = @_; my ($t, $u, $pl); local ($errmsg);
  L1:{
    $t = "($dat)"; ($t !~ m/[^\x20-\x7e]/) or last;
    (defined($pl = pl_parse_list($t))) or last;
    (vf_issafe_list($pl)) or last;
    $u = pl_form_list($pl, -1);
    return ['SPECIAL', $dat];
  }
  return ['SPEICALHEX', uc(unpack('H*', $dat))];
}

## vf_issafe_list($pl)
# Subcontractor of vf_dvi_special.
sub vf_issafe_list
{
  my ($pl) = @_; my ($ent);
  foreach $ent (@$pl) {
    if (ref $ent) {
      (vf_issafe_list($ent)) or return 0;
    } elsif ($ent =~ /^[CKDFOHR]$/ || $ent eq 'COMMENT') {
      return 0;
    }
  }
  return 1;
}

## vf_dvi_dumb_parse($dat)
# Subcontractor of dvi_parse.
sub vf_dvi_dumb_parse
{
  my ($dat) = @_;
 my ($t);
  $t = uc(unpack("H*", $dat));
  return ['MAP', ['DIRECTHEX', $t]];
}

##<*> vf_form($pl)
# Inverse of vf_parse.
sub vf_form
{
  my ($pl) = @_;
  my ($t, $u, $v, $pe, @fs, @chds, @cfds, @ccps);
  @chds = (247, 202, "", 0, 10 * TU);
  foreach $pe (@$pl) {
    if ($pe->[0] eq 'VTITLE') {
      ($#$pe <= 1) or return vf_fsynerror("bad argument", $pe);
      (length($pe->[1]) <= 255)
        or return vf_fsynerror("VTITLE string too long", $pe->[1]);
      $chds[2] = $pe->[1];
    } elsif ($pe->[0] eq 'CHECKSUM') {
      ($#$pe == 2 && defined($t = pl_value($pe, 1)))
        or return vf_fsynerror("bad argument", $pe);
      $chds[3] = $t;
    } elsif ($pe->[0] eq 'DESIGNSIZE') {
      ($#$pe == 2 && defined($t = pl_value($pe, 1)))
        or return vf_fsynerror("bad argument", $pe);
      $chds[4] = $t;
    } elsif ($pe->[0] eq 'MAPFONT') {
     ($#$pe >= 2  && defined($t = pl_value($pe, 1)))
       or return vf_fsynerror("bad argument", $pe);
      ($u, $t) = pack_num($t);
      @fs = ($u + 242, $t, 0, TU, 10 * TU, 0, 0, '', '');
      foreach $pe (@{$pe}[3 .. $#$pe]) {
        if (!ref $pe) {
          return vf_fsynerror("unexpected bareword", $pe);
        } elsif ($pe->[0] eq 'FONTCHECKSUM') {
          ($#$pe == 2  && defined($fs[2] = pl_value($pe, 1)))
            or return vf_fsynerror("bad argument", $pe);
        } elsif ($pe->[0] eq 'FONTAT') {
          ($#$pe == 2  && defined($fs[3] = pl_value($pe, 1)))
            or return vf_fsynerror("bad argument", $pe);
        } elsif ($pe->[0] eq 'FONTDSIZE') {
          ($#$pe == 2  && defined($fs[4] = pl_value($pe, 1)))
            or return vf_fsynerror("bad argument", $pe);
        } elsif ($pe->[0] eq 'FONTAREA') {
          ($#$pe == 1  && length($pe->[1]) <= 255)
            or return vf_fsynerror("bad argument", $pe);
          $fs[7] = $pe->[1]; $fs[5] = length($pe->[1]);
        } elsif ($pe->[0] eq 'FONTNAME') {
          ($#$pe == 1  && length($pe->[1]) <= 255)
            or return vf_fsynerror("bad argument", $pe);
          $fs[8] = $pe->[1]; $fs[6] = length($pe->[1]);
        } elsif (!$vf_strict) {
          return vf_fsynerror("unknown property", $pe);
        }
      }
      push(@cfds, pack("Ca*NNNCCa*a*", @fs));
    } elsif ($pe->[0] eq 'CHARACTER') {
     ($#$pe >= 2  && defined($t = pl_value($pe, 1)))
       or return vf_fsynerror("bad argument", $pe);
      $v = 0; $u = undef;
      foreach $pe (@{$pe}[3 .. $#$pe]) {
        if (!ref $pe) {
          return vf_fsynerror("unexpected bareword", $pe);
        } elsif ($pe->[0] eq 'CHARWD') {
          ($#$pe == 2  && defined($v = pl_value($pe, 1)))
            or return vf_fsynerror("bad argument", $pe);
        } elsif ($pe->[0] eq 'MAP') {
          (defined($u = vf_dvi_form($pe, $t))) or return;
        } elsif (!$vf_strict) {
          return vf_fsynerror("unknown property", $pe);
        }
      }
      if (!defined $u) {
        $u = pl_cook(['MAP', ['SETCHAR']]);
        (defined($u = vf_dvi_form($u, $t))) or return;
      }
      if (0 <= $t && $t <= 255 && 0 <= $v && $v <= 0xFFFFFF &&
          length($u) <= 241) { # short form
        @fs = (length($u), $t, substr(pack('N', $v), 1), $u);
        push(@ccps, pack("CCa3a*", @fs));
      } else {
        @fs = (242, length($u), $t, $v, $u);
        push(@ccps, pack("CNNNa*", @fs));
      }
    } elsif ($vf_strict) {
      return vf_fsynerror("unknown property", $pe);
    }
  }
  $t = pack("CCC/a*NN", @chds);
  $t = join('', $t, @cfds, @ccps);
  $t .= "\xf8" x (4 - length($t) % 4);
  return $t;
}

## vf_dvi_form($pl, $cc)
# Subcontractor of vf_form
sub vf_dvi_form
{
  my ($pl, $cc) = @_;
  my ($t, $u, $v, $l, $pe, $stk, @cnks);
  $stk = [{}];
  foreach $pe (@{$pl}[1 .. $#$pl]) {
    if ($pe->[0] eq 'SETCHAR') {
      if ($#$pe == 0) { $t = $cc; }
      elsif ($#$pe == 2 && defined($t = pl_value($pe, 1))) {
      } else { return vf_fsynerror("bad argument", $pe); }
      if (0 <= $t && $t <= 127) {
        push(@cnks, chr($t));
      } else {
        ($l, $t) = pack_num($t);
        push(@cnks, pack("Ca*", $l + 127, $t));
      }
    } elsif ($pe->[0] eq 'SETRULE') {
      ($#$pe == 4 && defined($t = pl_value($pe, 1)) &&
        defined($u = pl_value($pe, 3)))
        or return vf_fsynerror("bad argument", $pe);
      push(@cnks, pack("CNN", 132, $t, $u));
    } elsif ($pe->[0] eq 'PUSH') {
      push(@$stk, {}); push(@cnks, chr(141));
    } elsif ($pe->[0] eq 'POP') {
      pop(@$stk); (@$stk) or vf_fsynerror("cannot POP (char $cc)");
      push(@cnks, chr(142));
    } elsif ($pe->[0] eq 'MOVERIGHT') {
      (defined($t = vf_dvi_f_move($pe, $stk->[-1], 'r',+1))) or return;
      push(@cnks, $t);
    } elsif ($pe->[0] eq 'MOVELEFT') {
      (defined($t = vf_dvi_f_move($pe, $stk->[-1], 'r',-1))) or return;
      push(@cnks, $t);
    } elsif ($pe->[0] eq 'MOVEDOWN') {
      (defined($t = vf_dvi_f_move($pe, $stk->[-1], 'd',+1))) or return;
      push(@cnks, $t);
    } elsif ($pe->[0] eq 'MOVEUP') {
      (defined($t = vf_dvi_f_move($pe, $stk->[-1], 'd',-1))) or return;
      push(@cnks, $t);
    } elsif ($pe->[0] eq 'SELECTFONT') {
      ($#$pe == 2 && defined($t = pl_value($pe, 1)))
        or return vf_fsynerror("bad argument", $pe);
      if (0 <= $t && $t <= 63) {
        push(@cnks, chr($t + 171));
      } else {
        ($l, $t) = pack_num($t);
        push(@cnks, pack("Ca*", $l + 234, $t));
      }
    } elsif ($pe->[0] eq 'SPECIAL') {
      $t = pl_form_list($pe, -1);
      ($t =~ m|^\(SPECIAL\s?(.*)\)$|) or return fatal("vf_dvi_form");
      $u = $1; ($l, $t) = pack_num(length($u));
      push(@cnks, pack("Ca*a*", 238 + $l, $t, $u));
    } elsif ($pe->[0] eq 'SPECIALHEX') {
      ($u = join('', @{$pe}[1 .. $#$pl])) =~ s/\s+//g;
      ($u =~ m/^([0-9A-Fa-f]{2})+$/)
        or return vf_fsynerror("bad arguments", $pe);
      $u = pack("H*", $u); ($l, $t) = pack_num(length($u));
      push(@cnks, pack("Ca*a*", 238 + $l, $t, $u));
    } elsif ($pe->[0] eq 'DIR') {
      ($#$pe == 2 && defined($t = pl_value($pe, 1)) && $t <= 1)
        or return vf_fsynerror("bad argument", $pe);
      push(@cnks, pack("CC", 255, $t));
    } elsif ($pe->[0] eq 'DIRECTHEX') {
      ($u = join('', @{$pe}[1 .. $#$pl])) =~ s/\s+//g;
      ($u =~ m/^([0-9A-Fa-f]{2})+$/)
        or return vf_fsynerror("bad arguments", $pe);
      $u = pack("H*", $u); push(@cnks, $u);
    } else {
      return vf_fsynerror("unknown DVI operator: ", $pe);
    }
  }
  return join('', @cnks);
}

## vf_dvi_f_move($pe, $stk, $r, $sgn)
# Subcontractor of vf_dvi_form.
sub vf_dvi_f_move
{
  my ($pe, $stk, $r, $sgn) = @_; my ($v, $l, $t, $w, $x, $b);
  ($#$pe == 2 && defined($v = pl_value($pe, 1)))
    or return vf_fsynerror("bad argument", $pe);
  if ($sgn < 0) { $v = -$v; }
  ($l, $t) = pack_snum($v);
  ($w, $x, $b) = ($r eq 'r') ? ('w', 'x', 142) : ('y', 'z', 156);
  if ($vf_simple_move_code) { $t = pack("Ca*", $b + $l, $t); }
  elsif (!exists $stk->{$w}) {
    $stk->{$w} = $v; $t = pack("Ca*", $b + $l + 5, $t);
  } elsif ($stk->{$w} == $v) { $t = chr($b + 5); }
  elsif (!exists $stk->{$x}) {
    $stk->{$x} = $v; $t = pack("Ca*", $b + $l + 10, $t);
  } elsif ($stk->{$x} == $v) { $t = chr($b + 10); }
  else { $t = pack("Ca*", $b + $l, $t); }
  return $t;
}

## vf_fsynerror($msg)
# Error messages in vf_form.
sub vf_fsynerror
{
  my ($msg, $pl) = @_;
  if (ref $pl) { $pl = pl_form_list($pl, -1); }
  return error("VPL syntax error: $msg: $pl");
}

##<*> vf_for_mapping($map, $fn, $rmt)
#
sub vf_for_mapping
{
  my ($map, $fn, $rmt) = @_; my ($e, $pe, $pe2, $pl, %hrmt);
  if (defined $rmt) {
    foreach (@$rmt) { $hrmt{$_->[0]} = $_; }
  }
  (defined($map = arraymap($map))) or return;
  $pl = pl_header_vpl({});
  push(@$pl, pl_cook(['MAPFONT', 'D', 0, ['FONTNAME', $fn]]));
  foreach $e (@$map) {
    if (defined $rmt && !defined $hrmt{$e->[0]}) { next; }
    $pe = pl_cook(['CHARACTER', 'C', 0,
                   ['MAP', ['SETCHAR', 'C', 0]]]);
    pl_set_value($pe, 1, $e->[0]);
    pl_set_value($pe->[3][1], 1, $e->[1]);
    if (defined $rmt) {
      $pe2 = pl_cook(['CHARWD', 'R', 0]);
      pl_set_real($pe2, 1, $hrmt{$e->[0]}[1]);
      splice(@$pe, 3, 0, $pe2);
    }
    push(@$pl, $pe);
  }
  return $pl;
}

##<*> vf_mapfont($pl, $fn)
# Returns the FONTNAME value of MAPFONT id $fn in VPL $pl.
# If $fn is undef then it returns ref to the hash that maps
# id to fontmame.
sub vf_mapfont
{
  my ($pl, $fn) = @_; my ($t, $pe, $pe2, %hsh);
  foreach $pe (@$pl) {
    if ($pe->[0] eq 'MAPFONT') {
      ($pe2) = grep { $_->[0] eq 'FONTNAME' } (@{$pe}[3 .. $#$pe]);
      (defined $pe2) or next;
      if (!defined $fn) {
        $hsh{pl_value($pe, 1)} = $pe2->[1];
      } elsif (defined($t = pl_value($pe, 1)) && $t == $fn) {
        return $pe2->[1];
      }
    }
  }
  return (defined $fn) ? () : \%hsh;
}

##<*> vf_set_mapfont($pl, $fn, $fnam)
# Sets the FONTNAME value of MAPFONT id $fn to $fname
# in VPL $pl.
sub vf_set_mapfont
{
  my ($pl, $fn, $fnam) = @_; my ($t, $pe, $pe2, %hsh);
  foreach $pe (@$pl) {
    if ($pe->[0] eq 'MAPFONT' &&
        defined($t = pl_value($pe, 1)) && $t == $fn) {
      ($pe2) = grep { $_->[0] eq 'FONTNAME' } (@{$pe}[3 .. $#$pe]);
      (defined $pe2) or return 0;
      $pe2->[1] = $fnam; return 1;
    }
  }
  return 0;
}

##-------- Procedures on ZVP format

my %vf_zvp_category = (
# 1: to JPL, 2: to ZVP0, 3: both, 0: special
  DIRECTION         => 1,
  VTITLE            => 2,
  FAMILY            => 1,
  FACE              => 1,
  HEADER            => 1,
  CODINGSCHEME      => 1,
  DESIGNUNITS       => 1,
  DESIGNSIZE        => 3,
  CHECKSUM          => 3,
  SEVENBITSAFEFLAG  => 1,
  FONTDIMEN         => 1,
  BOUNDARYCHAR      => 1,
  MAPFONT           => 2,
  LIGTABLE          => 1,
  GLUEKERN          => 0,
  CODESPACE         => 0,
  CHARSINTYPE       => 0,
  CHARSINSUBTYPE    => 0,
  TYPE              => 0,
  SUBTYPE           => 0,
  CHARACTER         => 0,
);
my %vf_zvp_category_char = (
  CHARWD            => 0,
  CHARHT            => 2,
  CHARDP            => 3,
  CHARIC            => 4,
);

##<*> debug_vf_form($val)
our ($debug_vf_form);
sub debug_vf_form { $debug_vf_form = $_[0]; }

##<*> vf_form_ex($pl)
# Converts ZPL $pl to VF $vf and TFM $tfm and returns pair
# ($vf, $tfm).
sub vf_form_ex
{
  my ($pl) = @_; my ($plv, $plt, $vf, $tfm);
  (($plv, $plt) = vf_divide_zvp($pl)) or return;
  if ($debug_vf_form) {
    return (pl_form($plv), pl_form($plt));
  }
  (defined($vf = vf_form($plv))) or return;
  (defined($tfm = jfm_form($plt))) or return;
  return ($vf, $tfm);
}


## vf_divide_zvp($pl)
# Subcontractor of vf_form_ex. Divides $pl into ZVP0 part
# $plv and ZPL part $plt and returns ($plv, $plt).
sub vf_divide_zvp
{
  my ($pl) = @_; my ($t, $u, $k, $pe, $pe2, @v);
  my ($tyd1, $zcat, $rpe, $cspc, @cit, @cist, $glkrn);
  my (@plv, @plt, @tydsc, @stydsc, %char, %type, %stype);
  # First I classify each enry in $pl into @plv (ZVP0 part)
  # and @plt (ZPL part) and extract necessary information
  # to @cit, @tydsc, etc.
    # $cspc is charlist describing codespace
    # $cit[$t] is charlist of type $t
    # $cist[$t][$u] is charlist of subtype $t $u
    # $tydsc[$t] is 'description' of type $t
    # $stydsc[$t][$u] is 'description' of subtype $t $u
    # $char{$cc} is 'description' of char $cc
    # Here 'description' is the pair of CHARWD and MAP.
    # Currenetly CHARWD specified for subtypes and characters
    # are ignored (values set for corresponding types are
    # used), thus CHARWD entry of descriptions of subtypes
    # and chars are unused.
  foreach $pe (@$pl) {
    (defined($zcat = $vf_zvp_category{$pe->[0]})) or next;
    if ($zcat & 2) { push(@plv, $pe); }
    if ($zcat & 1) { push(@plt, $pe); }
    if ($zcat == 0) {
      if ($pe->[0] eq 'GLUEKERN') {
        $glkrn = $pe;
      } elsif ($pe->[0] eq 'CODESPACE') {
        if ($#$pe == 1 && !ref $pe->[1]
            && $pe->[1] =~ m/^[\w\-]{6,}$/) {
          $t = uc($pe->[1]);
          (defined($cspc = jfm_charlist($t)))
            or return error("unknown charlist name '$t'");
        } else {
          $cspc = jfm_grab_charlist($pe, 1);
        }
      } elsif ($pe->[0] eq 'CHARSINTYPE') {
        (defined($t = pl_value($pe ,1))) or return;
        (0 < $t && $t < 256)
          or return error("CIT with invalid type number ($t)");
        $cit[$t] = jfm_grab_charlist($pe, 3);
      } elsif ($pe->[0] eq 'CHARSINSUBTYPE') {
        (defined($t = pl_value($pe, 1))) or return;
        (0 <= $t && $t < 256)
          or return error("CIST with invalid type number ($t)");
        (defined($u = pl_value($pe, 3))) or return;
        (0 < $u && $u < 0x10000)
          or return error("CIST with invalid subtype number ($u)");
        $cist[$t][$u] = jfm_grab_charlist($pe, 5);
      } elsif ($pe->[0] eq 'TYPE') {
        (defined($t = pl_value($pe, 1))) or return;
        (0 <= $t && $t < 256)
          or return error("TYPE with invalid type number ($t)");
        $tyd1 = $tydsc[$t] = [ ];
        for ($k = 3; $k <= $#$pe; $k++) {
          $pe2 = $pe->[$k];
          if (defined($u = $vf_zvp_category_char{$pe2->[0]})) {
            $tyd1->[$u] = $pe2;
          } elsif ($pe2->[0] eq 'MAP') { $tyd1->[1] = $pe2; }
        }
      } elsif ($pe->[0] eq 'SUBTYPE') {
        (defined($t = pl_value($pe, 1))) or return;
        (0 <= $t && $t < 256)
          or return error("SUBTYPE with invalid type number ($t)");
        (defined($u = pl_value($pe, 3))) or return;
        (0 < $u && $u < 0x10000)
          or return error("SUBTYPE with invalid subtype number ($u)");
        $tyd1 = $stydsc[$t][$u] = [ ];
        for ($k = 5; $k <= $#$pe; $k++) {
          $pe2 = $pe->[$k];
          if (defined($u = $vf_zvp_category_char{$pe2->[0]})) {
            $tyd1->[$u] = $pe2;
          } elsif ($pe2->[0] eq 'MAP') { $tyd1->[1] = $pe2; }
        }
      } elsif ($pe->[0] eq 'CHARACTER') {
        (defined($t = pl_value($pe ,1))) or return;
        (0 <= $t && $t <= 0xFFFFFF)
          or return error("char code out of range ($t)");
        $tyd1 = $char{$t} = [ ];
        for ($k = 3; $k <= $#$pe; $k++) {
          $pe2 = $pe->[$k];
          # only MAP is significant
          if ($pe2->[0] eq 'MAP') { $tyd1->[1] = $pe2; }
          # tyd1->[0] is currently unused
        }
      }
    }
  }
      # default codespace is GL94DB
  (defined $cspc) or $cspc = jfm_charlist('GL94DB');
  # Next I check consistency about existence of entries
  # (e.g. CIT 4 should exist iff TYPE 4 exists).
  ($#cist >= 0 && $#cit < 0) and $#cit = 0;
  (defined $tydsc[0])
    or return error("no TYPE for type 0");
  (vf_check_match("TYPE", \@tydsc, "CIT", \@cit, 1, "type"))
    or return;
  foreach (0 .. $#tydsc) {
    (vf_check_match("SUBTYPE", $stydsc[$_], "CIST", $cist[$_],
       1, "subtype $_")) or return;
  }
  # Next I recompile JFM properties for support of subtypes with different
  # CHARWD values; then I output the resulted GLUEKERN, CHARSIN... lists,
  # and TYPE lists.
  vf_recompile_gluekern($glkrn, \@cit, \@cist, \@tydsc, \@stydsc);
  if (defined $glkrn) { push(@plt, $glkrn); }
  foreach $t (0 .. $#cit) {
    (defined $cit[$t]) or next;
    local $jfm_forced_prefix = 'X';
    push(@plt, jfm_form_cit($t, $cit[$t]));
  }
  @v = sort { $a <=> $b } (values %vf_zvp_category_char);
  foreach $t (0 .. $#tydsc) {
    (defined($tyd1 = $tydsc[$t])) or next;
    $rpe = pl_cook(['TYPE', 'D', 0]); pl_set_value($rpe, 1, $t);
    push(@$rpe, grep { defined $_ } (@{$tyd1}[@v]));
    push(@plt, $rpe);  #qq
  }
  # Next I make hash %type from charcode to type and %stype
  # from charcode to subtype, converting from $cspc, @cit,
  # and @cist. The key set of %type is equal to codespace.
    # $type{$cc} is type of char $cc (can be 0)
    # $stype{$cc} is subtype of char $cc (cannot be 0)
  (vf_assign_type($cspc, \%type, \%stype, 0)) or return;
  foreach $t (1 .. $#cit) {
    (vf_assign_type($cit[$t], \%type, \%stype, $t)) or return;
  }
  foreach $t (0 .. $#cit) {
    foreach $u (1 .. $#{$cist[$t]}) {
      (vf_assign_type($cist[$t][$u], \%type, \%stype, $t, $u))
        or return;
    }
  }
  # Last I generate the char packet part of ZVP0, using
  # information gathered so far.
  $t = vf_generate_char_packet(\@tydsc, \@stydsc,
         \%char, \%type, \%stype);
  push(@plv, @$t);
#print(pl_form(\@plv), ('-') x 60, "\n", pl_form(\@plt));exit;
  return (\@plv, \@plt);
}

## vf_generate_char_packet(...)
# Subcontractor of vf_divide_zvp. Generates the char packet
# part of ZVP0.
sub vf_generate_char_packet
{
  my ($tydsc, $stydsc, $char, $type, $stype) = @_;
  my ($t, $pe, $ty, $cc, @ccs, @pl);
  @ccs = sort { $a <=> $b } (keys %$type);
  foreach $cc (@ccs) {
    $pe = pl_cook(['CHARACTER', 'C', 0]);
    pl_set_value($pe, 1, $cc);
    $ty = $type->{$cc};
    push(@$pe, $tydsc->[$ty][0]); # CHARWD entry
    # add MAP entry
    if (defined($t = $char->{$cc})) {
      push(@$pe, $t->[1]);
    } elsif (defined($t = $stype->{$cc})) {
      push(@$pe, $stydsc->[$ty][$t][1]);
    } else {
      push(@$pe, $tydsc->[$ty][1]);
    }
    push(@pl, $pe);
  }
  return \@pl;
}

sub vf_recompile_gluekern
{
  my ($glkrn, $cit, $cist, $tydsc, $stydsc) = @_;
  my ($t, $u, $tyd0, $tyd, $ty, $nty, $sty, $nsty);
  my (@tyrel, @tygrp, $orgnty, @glkrn1);
  $orgnty = $#$tydsc;
  # type migration
  for ($ty = 0; $ty <= $#$tydsc; $ty++) {
    (defined $tydsc->[$ty]) or next;
    undef $nty; $tyd0 = $tydsc->[$ty];
    foreach $sty (1 .. $#{$stydsc->[$ty]}) {
      (defined $stydsc->[$ty][$sty]) or next;
      $tyd = $stydsc->[$ty][$sty];
      (defined $tyd->[1]) or $tyd->[1] = pl_clone($tyd0->[1]);
      if (vf_resolve_metric($tyd0, $tyd)) { next; }
      if (defined $nty) {
        $nsty = ($#{$stydsc->[$nty]} + 1 || 1);
        $stydsc->[$nty][$nsty] = $stydsc->[$ty][$sty];
#print("move $ty/$sty to $nty/$nsty\n");
#print("CIT/$nty ", dumpp($cit->[$nty]), " -> ");
        vf_clist_add($cit->[$nty], $cist->[$ty][$sty]);
        $cist->[$nty][$nsty] = $cist->[$ty][$sty];
#print(dumpp($cit->[$nty]), "\n");
      } else {
        $nty = $#$tydsc + 1; $tyrel[$ty] = $nty;
        $tydsc->[$nty] = $stydsc->[$ty][$sty];
#print("move $ty/$sty to $nty\n");
        $cit->[$nty] = $cist->[$ty][$sty];
      }
#print("CIT/$ty ", dumpp($cit->[$ty]), " -> ");
      vf_clist_remove($cit->[$ty], $cist->[$ty][$sty]);
#print(dumpp($cit->[$ty]), "\n");
      undef $stydsc->[$ty][$sty]; undef $cist->[$ty][$sty];
    }
  }
  # compile @tygrp from @tyrel
  foreach $ty (0 .. $orgnty) {
    $tygrp[$ty] = $u = [$ty]; $t = $ty;
    while (defined $tyrel[$t]) { $t = $tyrel[$t]; push(@$u, $t); }
  }
  # create new GLUEKERN list
  foreach $u (@$glkrn) {
    if (ref $u &&
        ($u->[0] eq 'KRN' || $u->[0] eq 'GLUE' || $u->[0] eq 'LABEL')) {
      foreach $ty (@{$tygrp[pl_value($u, 1)]}) {
        $t = pl_sclone($u); pl_set_value($t, 1, $ty);
        push(@glkrn1, $t);
      }
    } else { push(@glkrn1, $u); }
  }
  @$glkrn = @glkrn1;
}
## vf_clise_remove(...)
# Subcontractor of vf_recompile_gluekern.
sub vf_clist_remove {
  my ($lst1, $lst2) = @_; my (%hs);
  vf_clist_check(\%hs, $lst1, 1); vf_clist_check(\%hs, $lst2);
  @$lst1 = sort { $a <=> $b } (keys %hs);
}

## vf_clise_add(...)
# Subcontractor of vf_recompile_gluekern.
sub vf_clist_add {
  my ($lst1, $lst2) = @_; my (%hs);
  vf_clist_check(\%hs, $lst1, 1); vf_clist_check(\%hs, $lst2, 1);
  @$lst1 = sort { $a <=> $b } (keys %hs);
}

## vf_clist_check(...)
# Subcontractor of vf_recompile_gluekern.
sub vf_clist_check {
  my ($hs, $clst, $val) = @_; my ($e, $sc, $ec);
  foreach $e (@$clst) {
    ($sc, $ec) = (ref $e) ? @$e : ($e, $e);
    foreach ($sc .. $ec) {
      if (defined $val) { $hs->{$_} = $val; } else { delete $hs->{$_}; }
    }
  }
}

## vf_resolve_metric(...)
# Subcontractor of vf_recompile_gluekern.
sub vf_resolve_metric {
  my ($tyd1, $tyd2) = @_; my ($wd1, $nam, $idx, $same);
  $same = 1;
  foreach $nam (keys %vf_zvp_category_char) {
    $idx = $vf_zvp_category_char{$nam};
    $wd1 = (defined $tyd1->[$idx]) ? pl_value($tyd1->[$idx], 1) : 0;
    if (defined $tyd2->[$idx]) {
      if ($wd1 != pl_value($tyd2->[$idx], 1)) { undef $same; }
    } else {
      $tyd2->[$idx] = pl_cook([$nam, 'R', 0]);
      pl_set_value($tyd2->[$idx], 1, $wd1);
    }
  }
  return $same;
}

## vf_assign_type($cl, $type, $stype, $ty, $sty)
# Subcontractor of vf_divide_zvp. If $sty is defined, it maps
# chars in $cl to $sty in hash $stype->[$ty]; otherwise it maps
# chars in$cl to $ty in hash $type.
sub vf_assign_type
{
  my ($cl, $type, $stype, $ty, $sty) = @_;
  my ($t, $c, $s, $e);
  foreach $c (@$cl) {
    ($s, $e) = (ref $c) ? @$c : ($c, $c);
    foreach ($s .. $e) {
      if (defined $sty) { # set subtype
        ($type->{$_} == $ty) or return error(
         sprintf("inconsistent subtype assignment to char %04X" .
                 " (subtype %s %s vs type %s)",
                 $_, $ty, $sty, $type->{$_}));
        (!defined $stype->{$_}) or return error(
         sprintf("subtype reassignment to char %04X" .
                 " (subtype %s vs %s)",
                 $_, $sty, $stype->{$_}));
        $stype->{$_} = $sty;
      } elsif ($ty != 0) { # set type >0
        (defined $type->{$_}) or return error(
         sprintf("type assignment (%s) to char out of codespace:" .
                 "char %04X",
                 $ty, $_));
        ($type->{$_} == 0) or return error(
         sprintf("type reassignment to char %04X" .
                 " (type %s vs %s)",
                 $_, $ty, $type->{$_}));
        $type->{$_} = $ty;
      } else {             # set type 0
        $type->{$_} = $ty;
      }
    }
  }
  return 1;
}

## vf_check_match($lbla, $lsta, $lblb, $lstb, $pos, $srt)
# Subcontractor of vf_divide_zvp.
sub vf_check_match
{
  my ($lbla, $lsta, $lblb, $lstb, $pos, $srt) = @_; my ($mpos);
  $mpos = ($#$lsta > $#$lstb) ? $#$lsta : $#$lstb;
  foreach ($pos .. $mpos) {
    if (defined $lsta->[$_] && !defined $lstb->[$_]) {
      return error("$lbla entry without matching $lblb ($srt $_)");
    } elsif (defined $lstb->[$_] && !defined $lsta->[$_]) {
      return error("$lblb entry without matching $lbla ($srt $_)");
    }
  }
  return 1;
}


##<*> vf_parse_ex($vf, $jfm)
sub vf_parse_ex
{
  my ($vf, $jfm) = @_; my ($plv, $plt, $cit, $typ);
  my ($pl, $tydsc, $chdsc, $cspc, $cist, $stydsc, $chdsc);
  $plv = vf_parse($vf) or return;
  ($plt, $cit, $typ) = jfm_half_parse($jfm) or return;
  ($pl, $tydsc, $chdsc) = vf_restructure($plv, $plt) or return;
  ($cspc, $cist, $stydsc, $chdsc) =
    vf_analyze_dimap($chdsc, $tydsc, $typ, $cit) or return;
  $pl = vf_compose_zvp($pl, $cspc, $cist, $stydsc, $chdsc);
  return $pl;
}

sub vf_restructure
{
  my ($plv, $plt) = @_; my ($t, $u, $pe, $zcat, %chk);
  my (@pl, @tydsc, %chdsc);
  # ZPL
  foreach $pe (@$plt) {
    $zcat = $vf_zvp_category{$pe->[0]};
    if ($zcat == 1) {
      push(@pl, $pe);
    } elsif ($zcat == 3) {
      push(@pl, $pe); $chk{$pe->[0]} = pl_value($pe, 1);
    } elsif ($zcat == 0) {
      if ($pe->[0] eq 'CHARSINTYPE' || $pe->[0] eq 'GLUEKERN') {
        push(@pl, $pe);
      } elsif ($pe->[0] eq 'TYPE') {
        push(@pl, $pe); $t = pl_value($pe, 1);
        $u = pl_cook(['MAP']); push(@$pe, $u);
        $tydsc[$t] = [$pe->[3], $u];
      }
    } elsif (!defined $zcat) {
      return fatal("vf_restructure");
    }
  }
  # ZVP0
  foreach $pe (@$plv) {
    $zcat = $vf_zvp_category{$pe->[0]};
    if ($zcat == 2) {
      push(@pl, $pe);
    } elsif ($zcat == 3 && $vf_strict) {
      $t = pl_value($pe, 1); $u = $chk{$pe->[0]};
      ($t == $u ||
       ($pe->[0] eq 'CHECKSUM' && ($t == 0 || $u == 0)))
        or return error("inconsistent value: ", $pe->[0]);
    } elsif ($zcat == 0) {
      if ($pe->[0] eq 'CHARACTER') {
        $t = pl_value($pe, 1);
        $chdsc{$t} = [$pe->[3], $pe->[4]];
      }
    } elsif (!defined $zcat) {
      return fatal("vf_restructure");
    }
  }
  return (\@pl, \@tydsc, \%chdsc);
}

## vf_analyze_dimap
sub vf_analyze_dimap
{
  my ($chdsc, $tydsc, $typ, $citpe) = @_;
  my ($t, $u, $k, $cc, @ccs, $pe, @fs, $ty, $chd, @dmaps, %cnt);
  my ($cspc, @cit, @cist, @stydsc, %chdsc2);
  #@dmaps = ({}) x scalar(@$tydsc);
  # coderange consistency
  @fs = sort { $a <=> $b } (keys %$typ);
  foreach $cc (@fs) {
    (defined $chdsc->{$cc}) and next;
    if ($vf_strict) {
      return error(sprintf("charpacket missing in VF: code %04X", $cc));
    }
    delete $typ->{$cc};
  }
  #
  @ccs = sort { $a <=> $b } (keys %$chdsc);
  foreach $cc (@ccs) {
    $ty = $typ->{$cc}; $chd = $chdsc->{$cc};
    push(@{$cit[$ty]}, $cc);
    if ($vf_strict) {
      (pl_value($tydsc->[$ty][0], 1) == pl_value($chd->[0], 1))
        or return error(
             sprintf("CHARWD value mismatch: code %04X", $cc));
    }
    $pe = vf_contract_selfcode($chd->[1], $cc);
    $t = pl_form_list($pe, -1);
    push(@{$dmaps[$ty]{$t}}, $cc);
  }
  #
  if (defined($t = jfm_charlist_name(\@ccs))) {
    $cspc = [ $t ];
  } else { $cspc = jfm_form_charlist(\@ccs); }
  foreach $ty (0 .. $#dmaps) {
    (defined($u = $dmaps[$ty])) or next;
    foreach (keys %$u) { $cnt{$_} = scalar(@{$u->{$_}}); }
    @fs = sort {
      $cnt{$b} <=> $cnt{$a} || $u->{$a}[0] <=> $u->{$b}[0]
    } (keys %$u);
    foreach $k (0 .. $#fs) {
      $u = $dmaps[$ty]{$fs[$k]};
      if ($k == 0 || ($cnt{$fs[$k]} > 1 && $k < 256)) {
        $cist[$ty][$k] = jfm_form_charlist($u);
        $stydsc[$ty][$k][1] =
          vf_contract_selfcode($chdsc->{$u->[0]}[1], $u->[0]);
      } else {
        foreach (@$u) {
          $chdsc2{$_}[1] = $chdsc->{$_}[1];
        }
      }
    }
    @{$tydsc->[$ty][1]} = @{$stydsc[$ty][0][1]};
    undef $cist[$ty][0]; undef $stydsc[$ty][0];
    if ($ty > 0) {
      $t = jfm_form_charlist($cit[$ty]);
      push(@{$citpe->[$ty]}, @$t);
    }
  }
  return ($cspc, \@cist, \@stydsc, \%chdsc2);
}

sub vf_compose_zvp
{
  my ($pl, $cspc, $cist, $stydsc, $chdsc) = @_;
  my ($t, $u, $ty, $sty, $cc, $pe);
  $pe = pl_cook(['CODESPACE']); push(@$pl, $pe);
  push(@$pe, @$cspc);
  foreach $ty (0 .. $#$stydsc) {
    foreach $sty (0 .. $#{$stydsc->[$ty]}) {
      if (defined($t = $cist->[$ty][$sty])) {
        $pe = pl_cook(['CHARSINSUBTYPE', 'D', 0, 'D', 0]);
        pl_set_value($pe, 1, $ty); pl_set_value($pe, 3, $sty);
        push(@$pe, @$t); push(@$pl, $pe);
      }
      if (defined($t = $stydsc->[$ty][$sty])) {
        $pe = pl_cook(['SUBTYPE', 'D', 0, 'D', 0]);
        pl_set_value($pe, 1, $ty); pl_set_value($pe, 3, $sty);
        push(@$pe, $t->[1]); push(@$pl, $pe);
      }
    }
  }
  foreach $cc (keys %$chdsc) {
    $pe = pl_cook(['CHARACTER', 'C', 0]);
    pl_set_value($pe, 1, $cc);
    push(@$pe, $chdsc->{$cc}[1]); push(@$pl, $pe);
  }
  pl_rearrange($pl);
  return $pl;
}

## vf_contract_selfcode
sub vf_contract_selfcode
{
  my ($pl, $cc) = @_; my ($k, $pe, $pl2);
  $pl2 = pl_sclone($pl);
  foreach $k (1 .. $#$pl2) {
    $pe = $pl2->[$k];
    if ($pe->[0] eq 'SETCHAR' &&
        $#$pe > 0 && pl_value($pe, 1) == $cc) {
      $pl2->[$k] = pl_cook(['SETCHAR']);
    }
  }
  return $pl2;
}

##<*> vf_expand_named_charlist
#
sub vf_expand_named_charlist {
  my ($pl) = @_; my ($t);
  ($pl->[0] eq 'CODESPACE') or return;
  (defined($t = jfm_charlist($pl->[1]))) or return;
  $t = jfm_form_charlist($t, 0);
  splice(@$pl, 1, 1, @$t);
}


######## 'jfm' section ########

# jfm_form (ZPL -> JFM)
#  Jx --[jc(x)=Ic(i)]-> i (!uptex?)--> Ji --[ppltotf]--> (JFM)
#  Ux --[uc(x)=Ic(i)]->   (uptex?)---> Ui --[uppltotf]->
#  Xx --[x=i]--------->
# K $ --[Ee($)=Ic(i)]->
# jfm_parse (JFM -> ZPL)
#  (JFM) (!uptex?)--[ptftopl]-> $ --[je($)=Ic(x)]-> Jx/Ux/Xx
#        (uptex?)--[uptftopl]-> $ --[ue($)=Ic(x)]->

# for jfm_injcode
my %jfm_pfx_ijc = ( J => KI_JIS, U => KI_UNI, X => undef );
my %jfm_ijc_pfx = ( reverse %jfm_pfx_ijc );

##<*> jfm_use_uptex_tool($sw)
# Decides if upTeX tools are used to do jfm_parse. Here truth
# value of $sw means upTeX-pltotf should/shouldn't be used.
our $jfm_use_uptex_tool = 0;
sub jfm_use_uptex_tool
{
  my ($sw) = @_; my ($t);
  $t = ($cmd_name{uptftopl} eq '' || $cmd_name{uppltotf} eq '');
  if ($sw && $t) { return error("upTeX tools disabled"); }
  $jfm_use_uptex_tool = $sw;
  return 1;
}

##<*> jfm_parse($jfm)
# Converts JFM data $jfm to a pl-struct describing ZPL.
sub jfm_parse
{
  my ($jfm) = @_; my ($pl, $cit, $typ);
  ($pl, $cit, $typ) = jfm_half_parse($jfm) or return;
  return jfm_record_cit($pl, $cit, $typ);
}

## jfm_half_parse($jfm)
# Converts JFM data $jfm to a 'half-parsed' form.
sub jfm_half_parse
{
  my ($jfm) = @_; my ($cmd, $pl, $map, $cit, $typ);
  if ($jfm_use_uptex_tool) {
    $pl = x_uptftopl($jfm) or return;
    jfm_interprocess($pl) or return;
    return jfm_grab_cit($pl, 'utf8', 'unicode');
  } else {
    $cmd = $cmd_name{tftopl} . ' -kanji=jis';
    (($jfm, $map) = jfm_parse_preprocess($jfm)) or return;
    $pl = x_tftopl($jfm, $cmd) or return;
    jfm_interprocess($pl) or return;
    return jfm_parse_postprocess($pl, $map);
  }
}

##<*> jfm_form($pl)
# Converts a pl-struct $pl describing a JPLZ to JFM data.
sub jfm_form
{
  my ($pl) = @_; my ($cmd, $map, $jfm);
  if ($jfm_use_uptex_tool) {
    local $jfm_forced_prefix = 'U';
    (defined($pl = jfm_normalize($pl))) or return;
    return x_pltotf($pl, $cmd_name{uppltotf});
  } else {
    $cmd = $cmd_name{pltotf} . ' -kanji=jis';
    ((($pl, $map) = jfm_form_preprocess($pl))) or return;
    $jfm = x_pltotf($pl, $cmd) or return;
    return jfm_form_postprocess($jfm, $map);
  }
}

## jfm_grab_cit($pl)
sub jfm_grab_cit
{
  my ($pl, $xjc, $ijc) = @_; my ($t, $cl, $ty, $pe);
  my (@pl2, %typ, @cit, @ccs);
  local ($jcode_ex) =
    (defined $xjc) ? $jcode_ex_sym{$xjc} : $jcode_ex;
  local ($jcode_in) =
    (defined $ijc) ? $jcode_in_sym{$ijc} : $jcode_in;
  foreach $pe (@$pl) {
    if ($pe->[0] eq 'CHARSINTYPE') {
      pl_cook_list($pe);
      (defined($ty = pl_value($pe, 1))) or return;
      $cl = jfm_grab_charlist($pe, 3) or return;
      foreach $t (@$cl) {
        if (ref $t) {
          foreach ($t->[0] .. $t->[1]) { $typ{$_} = $ty; }
        } else { $typ{$t} = $ty; }
      }
      $cit[$ty] = $t = pl_cook(['CHARSINTYPE', 'D', 0]);
      pl_set_value($t, 1, $ty); push(@pl2, $t);
    } else { push(@pl2, $pe); }
  }
  return (\@pl2, \@cit, \%typ);
}

## jfm_normalize($pl, $xjc, $ijc)
# Normalizes pl-struct $pl, i.e., converts ZPL to ordinary PL.
# Here $xjc and $ijc mean source and internal kanji codes that
# are effective in this process (unchanged if undef).
sub jfm_normalize
{
  my ($pl, $xjc, $ijc) = @_; my ($citpe, $typ);
  (($pl, $citpe, $typ) = jfm_grab_cit($pl, $xjc, $ijc)) or return;
  (defined($pl = jfm_record_cit($pl, $citpe, $typ))) or return;
  return $pl;
}

## jfm_record_cit($pl, $citpe, $typ)
# Assembles a half-parsed form to get a complete ZPL.
sub jfm_record_cit
{
  my ($pl, $citpe, $typ) = @_; my ($t, $u, $cc, @ccs, @cit);
  @ccs = sort { $a <=> $b } (keys %$typ);
  foreach $cc (@ccs) {
    push(@{$cit[$typ->{$cc}]}, $cc);
  }
  foreach $t (1 .. $#cit) {
    (defined $cit[$t]) or next;
    $u = jfm_form_charlist($cit[$t]);
    push(@{$citpe->[$t]}, @$u);
  }
  return $pl;
}

## jfm_form_preprocess
# Subcontactor of jfm_form.
sub jfm_form_preprocess
{
  my ($pl) = @_; my ($pl2, $cit, $typ, $jc, $cc, @ccs, %map);
  ((($pl2, $cit, $typ) = jfm_grab_cit($pl))) or return;
  @ccs = sort { $a <=> $b } (keys %$typ);
  $jc = 0x2121;
  foreach $cc (@ccs) {
    push(@{$cit->[$typ->{$cc}]}, sprintf("J%04X", $jc));
    $map{$jc} = $cc; $jc = jfm_nextcode($jc) or return;
  }
  return ($pl2, \%map);
}
  # Valid codespace in pltotf: [21-28|30-74][21-7F] (7238 chars)

## jfm_form_postprocess
# Subcontactor of jfm_form.
sub jfm_form_postprocess
{
  my ($jfm, $map) = @_; my ($k, $pct, $lct, $ct, @fs);
  @fs = unpack('nnnn', $jfm);
  ($#fs == 3 && $fs[2] * 4 == length($jfm) &&
   ($fs[0] == 9 || $fs[0] == 11)) or return;
  $pct = $fs[3] * 4 + 28; $lct = $fs[1] * 4;
  $ct = substr($jfm, $pct, $lct); @fs = unpack('n*', $ct);
  for ($k = 2; $k <= $#fs; $k += 2) {
    my $cc = $map->{$fs[$k]};
    $fs[$k] = ($cc & 0xFFFF); $fs[$k+1] |= ($cc >> 16 << 8);
  }
  $ct = pack('n*', @fs);
  return substr($jfm, 0, $pct) . $ct . substr($jfm, $pct + $lct);
}

## jfm_parse_preprocess
# Subcontactor of jfm_half_parse.
sub jfm_parse_preprocess
{
  my ($jfm) = @_; my ($k, $pct, $lct, $ct, @fs, $jc, %map);
  @fs = unpack('nnnn', $jfm);
  ($#fs == 3 && $fs[2] * 4 == length($jfm) &&
   ($fs[0] == 9 || $fs[0] == 11)) or return;
  $pct = $fs[3] * 4 + 28; $lct = $fs[1] * 4;
  $ct = substr($jfm, $pct, $lct); @fs = unpack('n*', $ct);
  for ($jc = 0x2121, $k = 2; $k <= $#fs; $k += 2) {
    $map{$jc} = ($fs[$k] | $fs[$k+1] >> 8 << 16);
    $fs[$k] = $jc; $fs[$k+1] &= 0xFF;
    $jc = jfm_nextcode($jc) or return;
  }
  $ct = pack('n*', @fs);
  $jfm = substr($jfm, 0, $pct) . $ct . substr($jfm, $pct + $lct);
  return ($jfm, \%map);
}

## jfm_parse_postprocess
# Subcontactor of jfm_half_parse.
sub jfm_parse_postprocess
{
  my ($pl, $map, $pfx) = @_; my ($cit, $typ, %typ2, $cc);
  ($pl, $cit, $typ) = jfm_grab_cit($pl, 'xjis', 'xjis') or return;
  foreach $cc (keys %$typ) {
    $typ2{$map->{$cc}} = $typ->{$cc};
  }
  return ($pl, $cit, \%typ2);
}

## jfm_nextcode($jc)
# Subcontactor of jfm_form_preprocess and jfm_parse_preprocess.
sub jfm_nextcode
{
  my ($jc) = @_;
  if ((++$jc & 0xFF) < 0x7F) { return $jc; }
  if ($jc == 0x747F) {
    return error("too many chars have non-zero type");
  } elsif ($jc == 0x287F) { $jc = 0x3021; }
  else { $jc += 162; }
  return $jc;
}

## jfm_injcode($f, $xc)
# Subcontactor of jfm_form_preprocess.
sub jfm_injcode
{
  my ($pfx, $xc) = @_; local ($jcode_ex);
  # Note: here encodings meant for 'internal' use are
  #   used as 'external' excoding.
  (defined($jcode_ex = $jfm_pfx_ijc{$pfx})) or return;
  if ($jcode_ex eq $jcode_in) { return $xc; }
  return jcode_ord(chr($xc >> 8) . chr($xc & 0xff));
}


## jfm_interprocess($pl)
sub jfm_interprocess
{
  my ($pl) = @_; my ($pe, $pe2, $ok);
  foreach $pe (@$pl) {
    if ($pe->[0] eq 'TYPE') {
      $ok = 1; pl_set_numtype($pe, 1, 'D') or return;
    } elsif ($pe->[0] eq 'CHARSINTYPE') {
      $ok = 1; pl_set_numtype($pe, 1, 'D') or return;
    } elsif ($pe->[0] eq 'GLUEKERN') {
      foreach $pe2 (@$pe) {
        (ref $pe2) or next;
        ($pe2->[0] eq 'LABEL' ||
         $pe2->[0] eq 'GLUE' || $pe2->[0] eq 'KRN') or next;
        pl_set_numtype($pe2, 1, 'D') or return;
      }
    }
  }
  ($ok) or return error("input TFM is not JFM");
  return 1;
}

##-------- Procedures on charlist

# A charlist is an array, each entry of which is either a code
# value or a array-ref consisting of two values, which means
# a code range. For example,
# [ 0x50, [ 0x100, 0x1FF ], 0x234 ]
# is a charlist consisting of 258 code values.

our %jfm_charlist_registry = (
  'UNICODE-BMP' => [ [0x0000, 0xFFFF] ],
  'GL94DB' => [ map { [ ($_ << 8) | 0x21, ($_ << 8) | 0x7E ] }
                    (0x21 .. 0x7E) ],
);

##<*> jfm_use_charlist_name()
our $jfm_use_charlist_name = 1;
sub jfm_use_charlist_name { $jfm_use_charlist_name = $_[0]; }

## jfm_charlist($name)
sub jfm_charlist
{
  return $jfm_charlist_registry{$_[0]};
}

## jfm_charlist_name($cl)
sub jfm_charlist_name
{
  my ($cl) = @_;
  my ($k, $f1, $f2, $l1, $l2, $cl2, $nam, @nams, $res);
  (@$cl && $jfm_use_charlist_name) or return;
  $f1 = (ref $cl->[0]) ? $cl->[0][0] : $cl->[0];
  @nams = sort { $a cmp $b } (keys %jfm_charlist_registry);
  L1:foreach $nam (@nams) {
    $cl2 = $jfm_charlist_registry{$nam};
    $f2 = (ref $cl2->[0]) ? $cl2->[0][0] : $cl2->[0];
    ($f1 == $f2) or next;
    if (!defined $l1) { $l1 = jfm_length_charlist($cl); }
    $l2 = jfm_length_charlist($cl2);
    ($l1 == $l2) or next;
    $cl = jfm_rangify_charlist($cl);
    ($#$cl == $#$cl2) or next;
    foreach $k (0 .. $#$cl) {
      if (ref $cl->[$k] && ref $cl2->[$k]) {
        ($cl->[$k][0] == $cl2->[$k][0] &&
         $cl->[$k][1] == $cl2->[$k][1]) or next L1;
      } elsif (!ref $cl->[$k] && !ref $cl2->[$k]) {
        ($cl->[$k] == $cl2->[$k]) or next L1;
      } else { next L1; }
    }
    $res = $nam; last L1;
  }
  return $res;
}

sub jfm_length_charlist
{
  my ($cl) = @_; my ($s);
  $s = 0;
  foreach (@$cl) {
    if (ref $_) { $s += $_->[1] - $_->[0] + 1; }
    else { $s += 1; }
  }
  return $s;
}

## for jfm_rangify_charlist()
our $jfm_rangify_threshold = 8;

## jfm_rangify_charlist($cl)
sub jfm_rangify_charlist
{
  my ($cl) = @_; my ($cc, $scc, $ecc,@cl2);
  foreach $cc (@$cl, []) {
    if (defined $scc && !ref $cc && $cc == $ecc + 1) {
      $ecc = $cc;
    } else {
      if (!defined $scc) { # do nothing
      } elsif ($ecc - $scc < $jfm_rangify_threshold) {
        push(@cl2, $scc .. $ecc);
      } else {
        push(@cl2, [$scc, $ecc]);
      }
      if (ref $cc) {
        push(@cl2, $cc); $scc = $ecc = undef;
      } else {
        $scc = $ecc = $cc;
      }
    }
  }
  pop(@cl2);
  return \@cl2;
}

## jfm_form_cit($ty, $cl, $sym)
sub jfm_form_cit
{
  my ($ty, $cl) = @_; my ($t, $pe);
  $pe = pl_cook(['CHARSINTYPE', 'D', 0]);
  pl_set_value($pe, 1, $ty);
  $t = jfm_form_charlist($cl, 0); push(@$pe, @$t);
  return $pe;
}

## jfm_form_charlist($cl, $swrng)
sub jfm_form_charlist
{
  my ($cl, $swrng) = @_; my ($cc, $pe, @cl2, $nf, $pfx);
  $pfx = $jfm_ijc_pfx{$jcode_in};
  $nf = ($pl_prefer_hex) ? 'H' : 'O';
  if (defined $jfm_forced_prefix) { $pfx = $jfm_forced_prefix; }
  (defined $swrng)
    or $swrng = (!defined $jcode_in && !defined $jfm_forced_prefix);
  if ($swrng) { $cl = jfm_rangify_charlist($cl); }
  foreach $cc (@$cl) {
    if (ref $cc) {
      $pe = pl_cook(['CTRANGE', $nf, 0, $nf, 0]);
      pl_set_value($pe, 1, $cc->[0]);
      pl_set_value($pe, 3, $cc->[1]);
      push(@cl2, $pe);
    } else {
      push(@cl2, sprintf("%s%04X", $pfx, $cc));
    }
  }
  return \@cl2;
}

## jfm_grab_charlist($pe, $pos)
sub jfm_grab_charlist
{
  my ($pe, $pos) = @_; my ($k, $e, $t, $u, $cc, @cl);
  for ($k = $pos; $k <= $#$pe; $k++) {
    $e = $pe->[$k];
    if (ref $e && $e->[0] eq CNUM) {
      (defined($cc = pl_value($pe, $k))) or return;
      push(@cl, $cc); ++$k;
    } elsif ($e =~ m/^([JUX])([0-9A-Fa-f]{1,6})$/) {
      if (!defined $jcode_in || $1 eq 'X') {
        push(@cl, hex($2));
      } else {
        (defined($cc = jfm_injcode($1, hex($2)))) or return;
        push(@cl, $cc);
      }
    } elsif ($e =~ m/^[^\x21-\x7e]/) {
      (defined($cc = jcode_ord($e)))
        or return error("malformed $cc kanji character: ",
                        unpack('H*', $e));
        push(@cl, $cc);
    } elsif (ref $e && $e->[0] eq 'CTRANGE') {
      (defined($t = pl_value($e, 1)) &&
       defined($u = pl_value($e, 3))) or return;
      push(@cl, [$t, $u]);
    } else {
      return error("illegal element in CHARSINTYPE: ", $e);
    }
  }
  return \@cl;
}

######## NOW UNDER CONSIDERATION...

##<*> ttf_generate_jpl($ffnt, $id)
# Read the metric of a TTF file $ffnt (in case of TTC index is given
# by $id) and generates the pl-struct describing JPL for the metric.
# It returns ($pl, $dv) where $pl is the resulted pl-struct and $dv
# is the resulted rounding error of height/depth.
sub ttf_generate_jpl
{
  my ($ffnt, $id, $in) = @_; my ($t, $fam, $map, $out);
  my ($jpl, $vpl, $opl, $rmt, $jrmt, $imt, $vmt, $fd, $plcp);
  $out = { };
  if (defined $in->{family}) { $fam = $in->{family}; }
  else { ($fam = $ffnt) =~ s|.*/(.*)|$1|; };
  # JPL
  if (defined $in->{map}) {
    $map = $in->{map};
    (defined($jrmt = tfm_map_rmt($rmt, $map)))
      or return error("remapping failed");
  } else {
    $jrmt = $rmt; $map = [ ];
    foreach (@$rmt) { $map->{$_->[0]} = $_->[0]; }
  }
  ($out->{dw}, $out->{dv}, $imt, $vmt) =
   tfm_reduce_jpl_x($jrmt, $in->{balance});
  (defined $vmt) or return error("failed in length reduction");
  $t = { family => $fam, codingscheme => $in->{codingscheme} };
  (defined($fd = pl_fontdimen_jpl_rmt($rmt)) &&
   defined($jpl = pl_header($t, $fd)) &&
   defined($plcp = pl_char_part_jpl($imt, $vmt, 1)))
    or return error("JPL generation failed");
  push(@$jpl, @$plcp);
  # VF
  $jrmt = tfm_reduced_metric($imt, $vmt);
  $vpl = vf_for_mapping($map, $in->{ofm}, $jrmt);
  # OPL
  $t = { family => $fam, codingscheme => 'UNICODE' };
  (defined($fd = pl_fontdimen_opl_rmt($rmt)) &&
   defined($opl = pl_header_opl($t, $fd, 0)) &&
   defined($plcp = pl_char_part($rmt)))
    or return error("OPL generation failed");
  push(@$opl, @$plcp);
  # done
  return ($jpl, $vpl, $opl, $out);
}

##<*> ttf_generate_jpl($ffnt, $id, $in)
# Read the metric of a TTF file $ffnt (in case of TTC index is given
# by $id) and generates the composite PL for the metric. Here $in is
# a hash ref containing the following valid keys:
#   ofm: OFM name, recorded in the VF file
#   map: mapping table (either in array or hash form)
#   balance: balance factor applied in length reduction
#   family: font family name (only of informative use)
#   codingscheme: JFM codingscheme (only of informative use)
# It returns ($jpl, $vpl, $opl, $out), where the first three pl-structs
# describe JPL, VPL0 and OPL, and $out is a hash ref containing the
# following valid keys:
#   dw: maximum error of widths
#   dv: maximum error of heights/depths
sub ttf_generate_jpl_x
{
  my ($ffnt, $id, $in) = @_; my ($t, $fam, $map, $out);
  my ($jpl, $vpl, $opl, $rmt, $jrmt, $imt, $vmt, $fd, $plcp);
  $out = { };
  (defined($rmt = ttf_get_metric($ffnt, $id))) or return;
  if (defined $in->{family}) { $fam = $in->{family}; }
  else { ($fam = $ffnt) =~ s|.*/(.*)|$1|; };
  # JPL
  if (defined $in->{map}) {
    $map = $in->{map};
    (defined($jrmt = tfm_map_rmt($rmt, $map)))
      or return error("remapping failed");
  } else {
    $jrmt = $rmt; $map = { };
    foreach (@$rmt) { $map->{$_->[0]} = $_->[0]; }
  }
  ($out->{dw}, $out->{dv}, $imt, $vmt) =
   tfm_reduce_jpl_x($jrmt, $in->{balance});
  (defined $vmt) or return error("failed in length reduction");
  $t = { family => $fam, codingscheme => $in->{codingscheme} };
  (defined($fd = pl_fontdimen_jpl_rmt($rmt)) &&
   defined($jpl = pl_header($t, $fd)) &&
   defined($plcp = pl_char_part_jpl($imt, $vmt, 1)))
    or return error("JPL generation failed");
  push(@$jpl, @$plcp);
  # VF
  $jrmt = tfm_reduced_metric($imt, $vmt);
  $vpl = vf_for_mapping($map, $in->{ofm}, $jrmt);
  # OPL
  $t = { family => $fam, codingscheme => 'UNICODE' };
  (defined($fd = pl_fontdimen_opl_rmt($rmt)) &&
   defined($opl = pl_header_opl($t, $fd, 0)) &&
   defined($plcp = pl_char_part($rmt)))
    or return error("OPL generation failed");
  push(@$opl, @$plcp);
  # done
  return ($jpl, $vpl, $opl, $out);
}

######## 'config' section ########

## read_config()
sub read_config
{
  my ($t, $u, $err, @fs, $txt, @lins, %ent);
  ($t = $INC{"ZRTeXtor.pm"}) =~ s/\.\w{1,4}$//; $t .= ".cfg";
  (-f $t) or return;
  eval {
    (defined($txt = read_whole_file($t))) or die;
    @lins = split(m/\n/, $txt);
    foreach (@lins) {
      s/\#.*//; s/^\s+//; s/\s+$//;
      if ($_ eq '') { next; }
      (m/^(\w+)\s*=\s*(.*)/) or die;
      $ent{$1} = $2;
    }
    foreach (keys %ent) {
      $t = $ent{$_};
      if (exists $cmd_name{$_}) {
        if ($t =~ m/\s/) { $err = 1; }
        else { $cmd_name{$_} = $t; }
      } elsif ($_ eq 'jcode_in') {
        if (exists $jcode_in_sym{$t}) {
          $jcode_in = $jcode_in_sym{$t};
        } else { $err = 1; }
      } elsif ($_ eq 'jcode_ex') {
        if (exists $jcode_ex_sym{$t}) {
          $jcode_ex = $jcode_ex_sym{$t};
        } else { $err = 1; }
      }
    }
  };
  if ($@) { return error("read_config failed"); }
}

######## initialization
read_config();
get_temp_name_init();
if (defined $errmsg) { error("initialization failed"); }

######## all done
1;
# EOF
