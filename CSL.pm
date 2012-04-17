#!/usr/bin/perl

############################################################################

package CSL ;

############################################################################

=head1 CSL_Engine

  The module realises the integration of a CSL-compliant engine

=head1 PUBLIC METHODS

    process
   
=cut

use lib qw(../lib/extension ../lib/default);

use strict;
use warnings;

use LWP::UserAgent;

use Encode;
use JSON ;
use URI::Escape;

my $cfg;

=head2 new
 
  Object constructor

=cut

sub new {
  my $invocant = shift;
  my (%args) = @_;

  $cfg = $args{cfg};
  unless ($cfg) {
    require luurCfg;
    $cfg = luurCfg->new;
  }

  my ($local_status, @errors);

  my ($package,$file,$line) = caller;

  my $class = ref($invocant) || $invocant;

  my $self = bless {}, $class; 

  return $self;
}


=head2 process

 function to realize the integration of a CSL engine

 Parameter:

       style		- supported style format
 
       hash_ref 	- pointer to hash with bibliographic record information

=cut

sub process {

   my ($CSL, $style, $hash_ref) = @_ ;

   my $citeproc_url = $cfg->{csl_engine}->{url} ;

   my $csl_ref ; 

   my $start = 0 ;

   my $my_ua = LWP::UserAgent->new();

     # prepare the HTTP client

   $my_ua->agent('Netscape/4.75');
   $my_ua->from('agent@ub.uni-bielefeld.de');
   $my_ua->timeout(60);
   $my_ua->max_size(5000000); # max 5MB

   my @return_array ;

   my $limit = scalar (@{$hash_ref->{records}}) ;  #  number of records

   my $range =  $cfg->{csl_engine}->{recs} ;


   while ($start < $limit){     # calling the csl engine with packages to avoid http limits
      my %record_hash;

      my $i = 1 ;

      my $end ; 

      if ($start +  ($range - 1) > $limit){
  
         $end = $limit -  1;
      }
      else { $end = $start + $range -1 ; }

      foreach my $record (@{$hash_ref->{records}}[$start..$end]){

        my $key = sprintf ("%0.4d", $i) ; 

        $key =  $record->{recordid} ;      

        $record_hash{items}{$key}{id} =  $record->{recordid} ;      

        foreach my $unit (@{$record->{title}}){
               $record_hash{items}{$key}{title} =  encode_utf8($unit);
               last ;
        }

        $record_hash{items}{$key}{type} = $cfg->{csl_engine}->{type_map}{$record->{type}} ;    

        if ( $record->{publisher}){
           $record_hash{items}{$key}{publisher} =  encode_utf8($record->{publisher});
        }

        if ( $record->{place}){
           $record_hash{items}{$key}{'publisher-place'} =  encode_utf8($record->{place});
        }

        push (@{$record_hash{items}{$key}{issued}{'date-parts'}}, [$record->{publ_year}] ) ;

      foreach my $unit (@{$record->{author}}){

         my $author_hash = {} ;

         $author_hash->{family} = encode_utf8($unit->{family});
         $author_hash->{given} = encode_utf8($unit->{given});

          push (@{$record_hash{items}{$key}{author}}, $author_hash) ;
      }
      foreach my $unit (@{$record->{reviewer}}){

         my $author_hash = {} ;

         $author_hash->{family} = encode_utf8($unit->{family});
         $author_hash->{given} = encode_utf8($unit->{given});

          push (@{$record_hash{items}{$key}{author}}, $author_hash) ;
      }

      foreach my $unit (@{$record->{editor}}){

         my $editor_hash = {} ;

         $editor_hash->{family} = encode_utf8($unit->{family});
         $editor_hash->{given} = encode_utf8($unit->{given});

          push (@{$record_hash{items}{$key}{editor}}, $editor_hash) ;
      }

      foreach my $unit (@{$record->{host}}){

         if ($unit->{pages}){
            $record_hash{items}{$key}{page} = $unit->{pages} ;
         }
         elsif ($unit->{prange}){
            $record_hash{items}{$key}{page} = $unit->{prange} ;
         }

         if ( $unit->{issue}){
            $record_hash{items}{$key}{issue} = $unit->{issue} ;
         }
         if ( $unit->{title}){
            $record_hash{items}{$key}{'container-title'} = encode_utf8($unit->{title});
         }

         if ( $unit->{volume}){

            $record_hash{items}{$key}{volume} = $unit->{volume} ;
         }
      }
      foreach my $unit (@{$record->{series}}){

         if ( $unit->{issue}){
            $record_hash{items}{$key}{issue} = $unit->{issue} ;
         }

         $record_hash{items}{$key}{'collection-title'} = encode_utf8($unit->{title});

         if ( $unit->{volume}){

            $record_hash{items}{$key}{volume} = $unit->{volume} ;
         }
      }
    
      $i++ ;
    } # foreach
    $start += $range;

    my $json_citation = create_json (\%record_hash) ;

     $json_citation = uri_escape($json_citation);  # make the str url robust

     my  $temp_citeproc_url ;

     my $req_content = "data=$json_citation&style=$style&outputformat=$cfg->{csl_engine}{format}" ;

     my  $my_request = HTTP::Request->new (POST => $citeproc_url) ;
     $my_request->content_type('application/x-www-form-urlencoded');
     $my_request->content ($req_content) ;

     my  $my_response = $my_ua->request($my_request);

     my  $json = new JSON ;

     my $citation_ref = eval { $json->decode( $my_response->content) };
     # What would be a sensible behavior on citeproc failure?  Probably better
     # to report it than to silently proceed, but, on the other hand, it's
     # possible that a later citation in the batch may succeed.
     next if $@;

     $i = 0 ;
     foreach my $element ( @{$citation_ref->{bibliography}[1]}){

           my %temp ;
           $temp{id} = $citation_ref->{bibliography}[0]{entry_ids}[$i][0] ;
           
           $temp{citation} = $element;
           $i++ ; 
           push (@return_array, {%temp} ) ;
     }
   }  #while
 
   return \@return_array ;
}


=head2 create_json

 private function to create the JSON instance of a perl complex data structure in CSL format

 Parameter:

   $record_ref - reference on the data structure

=cut

sub create_json {

   my ($record_ref) = @_ ;

   my  $json = new JSON ;

   $json = $json->canonical(1) ;

   my $json_text = $json->encode($record_ref) ;

   return $json_text ;
}

1 ;
