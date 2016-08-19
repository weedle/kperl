#!/usr/bin/perl -w

package Kgrep::Test::FileTest;

use strict;
use warnings;

use FindBin;
use lib $FindBin::Bin . '/../../';

use Kgrep::FileModule;
use Package::Alias KFM => 'Kgrep::FileModule';
use Switch;


sub main
{
   if( @ARGV != 0 )
   {
      switch( $ARGV[0] )
      {
         case 1
	 {
	    test( "emptyFiles" );
	 }
	 case 2
	 {
            test( "fileList" );
	 }
      }
   } else {
      print 3 . "\n";
   }
}


main;





# Function: test
# purpose: run the smaller more specific test functions
# parameters: 
#    param1 [Array]: testParams is an array of strings determining what fns to test
# output: none
sub test
{
   my @testParams = @_;
   for my $testParam ( @testParams ) {
      if( $testParam eq "emptyFiles" ) {
         emptyFilesTest();
      }
      if( $testParam eq "fileList" ) {
         fileListTest();
      }
   }
}

# Function: emptyFilesTest
# purpose: test fn to empty file list
# parameters: none
# output: none
sub emptyFilesTest
{
   KFM::emptyFiles();
}

# Function: fileListTest
# purpose: test fn to list files in given file list
# parameters: none
# output: none
sub fileListTest
{
   KFM::fileList();
}
