# passwd.pl
#
# Routines for updating and checking user passwords
# 
# $Id: passwd.pl,v 1.4 2001-05-25 19:42:00 mcopenha Exp $
#

require "bob_db.pl";
require "dlg.pl";

sub
guess_pwd_win
{
  my $win_title = "Enter password";
  my $win_text = "Enter your password:";
  if (system("$DLG --title \"$win_title\" --clear --passwordbox \"" .
             $win_text .  "\" 8 45 2> $TMP/input.guess") != 0) {
    return undef;
  }

  return `cat $TMP/input.guess`;
}

sub
invalidPassword_win
{
  my $win_title = "Wrong password";
  my $win_text = "\nWrong password entered!\n";
  system("$DLG --title \"$win_title\" --msgbox \"" .
         $win_text .  "\" 7 30 2> /dev/null");
}


sub
pwd_win
{
  my ($userid) = @_;
  my $win_title = "Enter Password";
  my $win_text = q{
Type your new password.  To remove an existing
password do not enter any text.};

  my $verify_win_text = q{
Re-type your password:};

  my $passwd = &bob_db_get_pwd($userid);
  if (defined $passwd) {
    $salt = substr($passwd, -2, 2);
    $pwd_exists = 1;
  } else {
    $salt = "cB";
    $pwd_exists = 0;
  }

  if (system("$DLG --title \"$win_title\" --clear --cr-wrap --passwordbox \"" .
             $win_text .  "\" 10 50 2> $TMP/input.pwd") != 0) {
    return $CANCEL;
  }
  my $p = `cat $TMP/input.pwd`;

  if ($p eq "") {
    &bob_db_remove_pwd($userid);
    return;
  }

  if (system("$DLG --title \"$win_title\" --clear --passwordbox \"" .
             $verify_win_text .  "\" 9 50 2> $TMP/input.pwd_v") != 0) {
    return $CANCEL;
  }
  my $p_v = `cat $TMP/input.pwd_v`;

  if ($p ne $p_v) {
    my $no_match_msg = q{
There was a mismatch between the two 
passwords.  No changes were made.};
    system("$DLG --title \"Passwords Do Not Match\" --cr-wrap " .
           "--clear --msgbox \"" .  $no_match_msg .  "\" 8 42 2> /dev/null");
    return;
  }

  $c = crypt($p, $salt);
  if ($pwd_exists == 1) {
    &bob_db_update_pwd($userid, $c);
  } else {
    &bob_db_insert_pwd($userid, $c);
  }
}


sub
checkPwd
{
  my ($p, $guess) = @_;
  return (crypt($guess, $p) eq $p);
}

1;
