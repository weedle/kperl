#!/usr/bin/perl -w

package Kgrep::ColorModule;

use strict;
use warnings;

use Term::ANSIColor 2.00 qw( :pushpop );
use Term::ANSIColor 4.00 qw( RESET :constants256 );
use Switch;


################################
########## Constants ###########
################################
# Scalar: fileCol
# highlight color for file names in search results
my $fileCol = RGB135;

# Scalar: numCol
# highlight color for the file/line numbers
my $numCol = RGB114;

# Scalar: promptCol
# highlight color for the kgrep prompt
my $promptCol = RGB215;

# Scalar: textCol
# highlight color for text entered at the prompt, and other things
# if changed, also update the echostyle line in main
my $textCol = RGB025;

# Scalar: errCol
# highlight color for error messages
my $errCol = RGB523;

# Scalar: prompt
# prompt is just the main prompt of grep, I update it for each major set of changes
# v1: basic grep wrapper, only had search function and highlighted results
# v2: became its own shell of sorts, and had extra features like hcat and sl
# v3: management of results with fl, fs, plus a number of extra changes
# v4: number of bug fixes, revamped file handling and comments, added frs, fr
my $prompt = "kperl-v4: ";

################################
########## Functions ###########
################################

# Function: kcolor
# purpose: helper fn to color a specific string
# parameters:
#    param1 [Scalar]: i is the number used to determine the color
#    param2 [Scalar]: str is the string to be colored
# output: The colored string (escape sequence on both sides)
sub kcolor
{
   my $i = $_[0];
   my $str = $_[1];
   my $c = $i % 6;
   switch ( $c )
   {
      # These are pretty good settings for solarized light
      case 0 { return LOCALCOLOR RGB040 $str; } #GREEN
      case 1 { return LOCALCOLOR RGB025 $str; } #BLUE
      case 2 { return LOCALCOLOR RGB404 $str; } #MAGENTA
      case 3 { return LOCALCOLOR RGB043 $str; } #CYAN
      case 4 { return LOCALCOLOR RGB520 $str; } #YELLOW (or orangey really)
      case 5 { return LOCALCOLOR RGB400 $str; } #RED
   }
}

# Function: highlight
# purpose: helper function to highlight occurrences of a term in a string
# parameters:
#    param1 [Scalar]: i is used to pick the highlight color
#    param2 [Scalar]: str is the string to be highlighted
#    param3 [Scalar]: rest is the line to be processed
# output: string line with specified substring highlighted
sub highlight
{
   my $i = $_[0];
   my $str = quotemeta $_[1];
   my $rest = $_[2];
   my $found = $str;
   if( $rest =~ m/($_[1])/ )
   {
      $found = $1;
   }
   my $strReplaced = quotemeta kcolor( $i, $found );
   $rest =~ s#\\##g;
   $str =~ s#\\##g;
   $rest =~ s#$str#$strReplaced#g;
   return $rest;
}

# Function: format{Type}
# purpose: return {Type} in the right format/color
# parameters:
#    param1 [Scalar]: The var of type {Type} to format
# output: formatted string
sub formatFile
{
   my $r = LOCALCOLOR $fileCol, $_[0];
   return $r;
}

sub formatNum
{
   my $r = LOCALCOLOR $numCol, $_[0];
   return $r;
}

sub formatPrompt
{
   my $r = LOCALCOLOR $promptCol, $prompt;
   return $r;
}

sub formatText
{
   my $r = LOCALCOLOR $textCol, $_[0];
   return $r;
}

sub formatErr
{
   my $r = LOCALCOLOR $errCol, $_[0];
   return $r;
}

sub getPrompt
{
   return $prompt;
}

# Function: formatCustom
# purpose: for all other LOCALCOLOR calls
# parameters:
#    param1 [Scalar]: The color in a form ANSIColor 
#       would recognize
#    param2 [Scalar]: The thing to color
# output: formatted string
sub formatCustom
{
   my $r = LOCALCOLOR $_[0], $_[1];
   return $r;
}

return 1;
