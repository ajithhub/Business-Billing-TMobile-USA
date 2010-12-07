# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl NewModule.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use Test::More tests => 19;
use YAML;
BEGIN { use_ok('Business::Billing::TMobile::USA');
use_ok('YAML');

};

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.
#

use_ok('HTTP::Cookies');

my $cookie_file = 't/tmo_login_cookies.dat';
ok(-f $cookie_file, "Sample login cookie file is present");

my $cookie_jar = HTTP::Cookies->new(file => $cookie_file);
my $parsed_cookie = Business::Billing::TMobile::USA::_parse_login_cookies(cookie_jar => $cookie_jar);
isnt($parsed_cookie, undef,                   "Cookie parsing result is not undef");
is($parsed_cookie->{first_name},"John",       "Parse first name from cookie");
is($parsed_cookie->{full_name},"John+Smith",  "Parse full name from cookie");
is($parsed_cookie->{is_prepaid},"True",       "Parse is_prepaid from cookie");
is($parsed_cookie->{user},"8475551212",       "Parse username from cookie");

print YAML::Dump($parsed_cookie);


my $account_file = "t/out_ACCOUNT_GET.html";
my $refill_file  = "t/out_REFILL_GET.html";

ok(-f $account_file, "Sample account content file is present");
ok(-f $refill_file, "Sample refill content file is present");

my $text  = "";

{
    local $/ = undef;
    my $fh;
    open ($fh, '<', $account_file);
    $text .= <$fh>;
    close $fh;
    open ($fh, '<', $refill_file);
    $text .= <$fh>;
    close $fh;
}
isnt($text, "", "Text is not emtpy string after loaing files");

my $parsed_content= Business::Billing::TMobile::USA::_parse_refill_pages(content => $text);

is($parsed_content->{balance}, '$102.83', "Parsed dollar value");
is($parsed_content->{expiration}, '11/29/2011 12:00:00 AM', "Parsed expiration date");
is($parsed_content->{messages}, '1439', "parsed message balace");
is($parsed_content->{minutes}, '1005', "Parsed minute balance");
is($parsed_content->{next_charge}, 'N/A', "Parsed Next charge");
is($parsed_content->{phone_number}, '847-555-1212', "Parsed phone number");
is($parsed_content->{rate_plan_name}, 'Pay As You Go', "Parsed rate plan");
