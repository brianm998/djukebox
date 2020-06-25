#!/usr/bin/perl

use strict;

my $did_output = 0;

# XXX add encoding (mp3, etc)

my $filename = shift;

writeJson($filename);

sub writeJson {
  my ($filename) = @_;
  my $outputs = {};
  $outputs->{Filename} = $filename;
  my $json_filename = $filename;
  $filename =~ s/`/\\`/;
  $outputs->{SHA1} = $1 if(`sha1sum \"$filename\"` =~ /^([a-f0-9A-F]+)\s+/);
  open INPUT, "exiftool \"$filename\" |" || die "doh: $!";
  open my $output, ">$json_filename.json";
  print $output "{\n";
  if($json_filename =~ m~/?([^/]*)$~) {
    $outputs->{Filename} = $1;
  } else {
    $outputs->{Filename} = $json_filename;
  }
  while (<INPUT>) {
    if (/Audio Bitrate\s+:\s*(.*)\s*/) {
      $outputs->{AudioBitrate} = $1;
    } elsif (/Sample Rate\s+:\s*(.*)\s*/) {
      $outputs->{SampleRate} = $1;
    } elsif (/Title\s+:\s*(.*)\s*/) {
      $outputs->{Title} = $1;
    } elsif (/Artist\s+:\s*(.*)\s*/) {
      $outputs->{Artist} = $1;
    } elsif (/Conductor\s+:\s*(.*)\s*/) {
      $outputs->{Conductor} = $1;
    } elsif (/Band\s+:\s*(.*)\s*/) {
      $outputs->{Band} = $1;
    } elsif (/Album\s+:\s*(.*)\s*/) {
      $outputs->{Album} = $1;
    } elsif (/Year\s+:\s*(.*)\s*/) {
      $outputs->{Year} = $1;
    } elsif (/Comment\s+:\s*(.*)\s*/) {
      $outputs->{Comment} = $1;
    } elsif (/Track\s+:\s*(.*)\s*/) {
      $outputs->{TrackNumber} = $1;
    } elsif (/Genre\s+:\s*(.*)\s*/) {
      $outputs->{Genre} = $1;
    } elsif (m~Date/Time Original\s+:\s*(.*)\s*~) {
      $outputs->{OriginalDate} = $1;
    } elsif (/Duration\s+:\s*(.*)\s*/) {
      $outputs->{Duration} = $1;
    }
  }
  # handle files like this: Masterplan=Aeronautics=04=I`m_Not_Afraid.mp3
  $json_filename =~ s/_/ /g;
  $json_filename = $1 if($json_filename =~ m~/([^/]*)$~);

  if ($json_filename =~ m~^([^/=]+)=([^=]+)=([^=]+)=([^=]+)[.]~) {
    $outputs->{Artist} = $1;
    $outputs->{Band} = $1;
    $outputs->{Album} = $2;
    $outputs->{TrackNumber} = $3;
    $outputs->{Title} = $4;
  } elsif ($json_filename =~ m~^([^./=]+)=([^=]+)[.]~) {
    $outputs->{Artist} = $1;
    $outputs->{Band} = $1;
    $outputs->{Title} = $2;
  } else {
    warn "no regex for $json_filename\n";
  }

  $outputs->{Band} = $outputs->{Artist} unless defined $outputs->{Band};
  
  for my $key (keys %$outputs) {
    outputString($output, $key, $outputs->{$key});
  }
  print $output "\n}\n";
  close $output;
  close INPUT;
}

sub outputString {
  my ($fh, $name, $value) = @_;

  if (defined $value && $value ne '') {
    print $fh ",\n" if($did_output);
    print $fh "    \"$name\" : \"$value\"";
    $did_output = 1;
  }
}
