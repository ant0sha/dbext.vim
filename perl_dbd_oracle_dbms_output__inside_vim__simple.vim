" use as:
" $ vim \
" /data/repo/mop/Perl_Oracle_DBD_dbms_output/perl_dbd_oracle_dbms_output__inside_vim__simple.vim \
"  -c -c ':so % | call Check_my_perl__load()'
"
" in case $good = 0 (inside sub perl_dump_dbms_output_internal), encoding will
" come corrupted in some way in the output
"
" in case $good = 1 (inside sub perl_dump_dbms_output_internal), output is fine
"
function! Check_my_perl__load()

    perl << EOCore
require 5.8.0;
use strict;
use diagnostics;
use warnings;
use Data::Dumper qw( Dumper );
use utf8;
use open ':std', ':encoding(UTF-8)';
use DBD::Oracle qw(:ora_types);
use DBI;
use Encode;

my $dbh = ();
my @dbms_output = ();
my $inside_vim = 1;

sub my_say {
  print(join(" ", @_)."\n");
}
 
sub perl_connect() {
  $dbh = DBI->connect ('dbi:Oracle://<your_host_name>:1521/<your_instance_name>', "<your_user_name>", "<your_password_name>"
      , 
      {
        ## NOTE: those 2 settings are necessary on cygwin with
        # DBD::Oracle, otherwise no matter what is the value of
        # NLS_LANG, oracle does something strange. No idea how it
        # is determines what to return to us in case those are not
        # specified, but if we dont do like this we get anything
        # else but UTF8 on client side.
        ora_charset                     => 'AL32UTF8',
        ora_ncharset                    => 'AL32UTF8',
        #       ora_verbose                     => 6,
      }
    );
  if (!$dbh)
  {
    die ("Failed to connect to database: " . DBI->errstr);
  };

  #print "ora_can_unicode: " . $dbh->ora_can_unicode() . "\n";
  #print "ora_nls_parameters " . Dumper($dbh->ora_nls_parameters()) . "\n";

  $dbh->func( 1000000, 'dbms_output_enable' );
}

# Fetches all available rows of dbms_output from server
sub fetch_dbms_output
{
  my ($conn_local) = (@_);

  my $max_line_size = 32768; # anything we put here can be too short...
  #my $max_line_size = 500; # anything we put here can be too short...
  my $get_lines_st = $conn_local->prepare_cached("begin dbms_output.get_lines(:l,:n); end;");
  my $num_lines_asked = 500;
  my $num_lines = $num_lines_asked;
  my @lines = map { ''; } ( 1..$num_lines ); # create 500 elements array
  db_debug("\@lines size = ", scalar(@lines));
  my $lines_cur = \@lines;
  $get_lines_st->bind_param_inout(':l', \$lines_cur, $max_line_size, {ora_type => ORA_VARCHAR2_TABLE});
  $get_lines_st->bind_param_inout(':n', \$num_lines, 50, {ora_type => 1});

  $get_lines_st->execute();
  db_debug("executed get_lines() ok. num_lines fetched = $num_lines");

  my @text_2 = ();
  if ($num_lines) {
    push @text_2, @lines[0..($num_lines-1)]; # copy to @text array
  }

  while ($num_lines == $num_lines_asked) {
    $num_lines = $num_lines_asked;
    @lines = map { ''; } ( 1..$num_lines ); # create 500 elements array
    $get_lines_st->execute();
    db_debug("executed get_lines()/again ok. num_lines fetched = $num_lines");
    if ($num_lines) {
      push @text_2, @lines[0..($num_lines-1)]; # copy to @text array
    }
  }

  $get_lines_st = undef;

  ## max_line_size exceeded {
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  # it sounds like dirty hack. and it is in fact.
  # seems that if the max_line_size is exceeded in bind_param_inout for
  # ORA_VARCHAR2_TABLE, requested number (500) of completely empty (null)
  # strings are returned. That makes no real sense to me, but at least we
  # are trying to handle this condition "gracefully" - well, that has to
  # be told to called normally and caller has to decide, what means
  # "gracefully" in that case - we just replace all the NULL strings with
  # diagnostic string which is visible to caller and can be interpreted
  # by human eye at least.
  # more straight approach is to die() and let caller intercept us with
  # eval {} and how to proceed in case he recognize we had a problem here
  my $undefsFound = 0;
  LINE: for my $l (@text_2) {
    if (! defined($l)) {
      $undefsFound++;
      #last LINE;
    }
  }

  # only in case $num_lines_asked and "number of lines returned" - e.g. entries
  # count in @text_2 we have a problem. otherwise we assume it is really occasional
  # strings of size = 0 returned by server
  if ($undefsFound && $num_lines_asked == scalar(@text_2)) {
    die ("E: some <undefs> are found in result, requested: $num_lines_asked, returned: ".scalar(@text_2).", undef: $undefsFound");
  }

  ## if ($undefsFound) {
  ##   db_debug("undefs found in the dbms_output, probably max_line_size=$max_line_size were exceeded?");
  ##   my @text_3 = @text_2;
  ##   @text_2 = ();
  ##   for my $l (@text_3) {
  ##     if (! defined($l)) {
  ##       push @text_2, "max_line_size=$max_line_size exceeded?";
  ##     } else {
  ##       push @text_2, $l;
  ##     }
  ##   }
  ## }
  ## max_line_size exceeded }
  # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

  @text_2;
}

sub perl_exec_statement() {

  my $sql = "begin 
    dbms_output.put_line('We äre the Chämpiöns');
    dbms_output.put_line('Öf ä wörld...');
  end;";

  my $statement = $dbh->prepare($sql);
  $statement->execute();
  my_say("executed ok.");
  $statement->finish;
  $statement = undef;

  # @dbms_output = $dbh->func( 'dbms_output_get' );
  @dbms_output = fetch_dbms_output($dbh);
  my_say ("got count:".scalar(@dbms_output));
}

sub db_debug
{
  my $msg = shift;
  VIM::Msg('DBI-VIM::MSG:'.$msg, 'WarningMsg');
  my_say ("DBI-say:".$msg);
  return 0;
}

sub perl_dump_dbms_output_internal {
  my $good = 1;
  if (! @dbms_output) {
      return;
  }
  #my @dbms_out_copy = @dbms_output;
  for my $one_line (@dbms_output) {
    # decoded one line
    my $dol = $one_line;
    if ($good) { $dol = decode('utf8', ($one_line // '')); }
    db_debug("line: ".$dol);
  }

  my $joined_lines = join ("\n", @dbms_output); 
  if ($good) { $joined_lines = decode('utf8', $joined_lines); }
  db_debug("all_joined: ".$joined_lines);
}

sub perl_disconnect {
  $dbh->disconnect;
}

perl_connect;
perl_exec_statement;
perl_dump_dbms_output_internal;
perl_disconnect;

EOCore

endfunction
