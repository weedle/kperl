#!/usr/bin/perl -w

package Kgrep::Test::ColorTest;

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin . '/../../';

use Kgrep::ColorModule;
use Package::Alias KCM => 'Kgrep::ColorModule';
use Switch;

sub main
{
   if( @ARGV != 0 )
   {
      switch( $ARGV[0] )
      {
         case 1
	 {
	    test( "kcolor" );
	 }
	 case 2
	 {
	    test( "highlight" );  
	 }
	 case 3
	 {
	    test( "printType" );  
	 }
      }
   } else {
      print 3 . "\n";
   }
}


main;





# Function: kcolorTest
# purpose: test for fn kcolor
# parameters: no params
sub kcolorTest
{
   my $sentence = "";
   for my $i( 1 .. 9 ) {
      print( "kcolor( $i " . KCM::kcolor( $i, "test" ) . " )\n" );
      $sentence .= KCM::kcolor( $i, "$i" ) . " ";
   }
   print $sentence . "\n";
}

# Function: highlightTest
# purpose: test for fn highlight
# parameters: no params
sub highlightTest
{
   my $sentence1 = KCM::highlight( 1, "highlight", "highlight on random sentence" );
   my $sentence2 = KCM::highlight( 2, "on random", "highlight on random sentence" );
   my $sentence3 = KCM::highlight( 3, "sentence", "highlight on random sentence" );
   my $sentenceCompound = KCM::highlight( 4, "on", $sentence1 );
   $sentenceCompound = KCM::highlight( 5, "random", $sentenceCompound );
   $sentenceCompound = KCM::highlight( 6, "sentence", $sentenceCompound );
   $sentence1 =~ s#\\##g;
   $sentence2 =~ s#\\##g;
   $sentence3 =~ s#\\##g;
   $sentenceCompound =~ s#\\##g;
   print( $sentence1 . "\n" );
   print( $sentence2 . "\n" );
   print( $sentence3 . "\n" );
   print( $sentenceCompound . "\n" );
}

# Function: testType
# purpose: test for the different print{Type} functions
# parameters: no params
sub testType
{
   print "File: " . KCM::formatFile( "some file" ) . " remaining text\n";
   print "Number: " . KCM::formatNum( 32 ) . " remaining text\n";
   print "Prompt: " . KCM::formatPrompt . " remaining text\n";
   print "Text: " . KCM::formatText( "some text" ) . " remaining text\n";
   print "Error: " . KCM::formatErr( "some error" ) . " remaining text\n";
   print "Custom: " . KCM::formatCustom( KCM::RGB114, "some text" ) . " remaining text\n";
}



# Function: test
# purpose: run the smaller more specific test functions
# parameters: an array of strings determining what fns to test
sub test
{
   my @testParams = @_;
   for my $testParam ( @testParams ) {
      if( $testParam eq "kcolor" ) {
         kcolorTest;
      }
      if( $testParam eq "highlight" ) {
         highlightTest;
      }
      if( $testParam eq "printType" ) {
         testType;
      }
   }
}
