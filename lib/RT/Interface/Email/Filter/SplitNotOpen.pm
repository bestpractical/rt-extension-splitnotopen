package RT::Interface::Email::Filter::SplitNotOpen;

use warnings;
use strict;

use RT::Interface::Email qw(ParseCcAddressesFromHead);

=head1 NAME

RT::Interface::Email::Filter::SplitNotOpen - When someone replies to a closed ticket,
create a new one, rather than reopening the old one

=head1 DESCRIPTION


=cut

sub GetCurrentUser {
    my %args = (
        Message       => undef,
        RawMessageRef => undef,
        CurrentUser   => undef,
        AuthLevel     => undef,
        Action        => undef,
        Ticket        => undef,
        Queue         => undef,
        @_
    );

    unless ( $args{'CurrentUser'} ) {
        $RT::Logger->error(
            "Filter::SplitNotOpen executed when "
            ."CurrentUser (actor) is not authorized. "
            ."Most probably you want to add Auth::MailFrom plugin before."
        );
        return ( $args{'CurrentUser'}, $args{'AuthLevel'} );
    }

    # If the user isn't asking for a comment or a correspond,
    # bail out
    unless ( $args{'Action'} =~ /^(?:comment|correspond)$/i ) {
        return ( $args{'CurrentUser'}, $args{'AuthLevel'} );
    }

    my $ticket_as_user = RT::Ticket->new( $args{'CurrentUser'} );
    my $queue          = RT::Queue->new( $args{'CurrentUser'} );

    if ( !$queue->id ) {
        $queue->Load( $args{'Queue'}->id );
    }


    # We only want to run on resolved or rejected tickets
    if ( $args{'Ticket'}->id and $args{'Ticket'}->Status !~ /^(?:resolved|rejected)$/i)  {
            return ($args{'CurrentUser'}, $args{'AuthLevel'});
    } else {

        my %create_args = ();
        $create_args{'Queue'} = $args{'Queue'}->Id unless exists $create_args{'Queue'};

        # subject
            $create_args{'Subject'} = $args{'Message'}->head->get('Subject');

        my $test_name = $RT::EmailSubjectTagRegex || qr/\Q$RT::rtname\E/i;
            
         $create_args{'Subject'} =~ s/\[$test_name\s+\#(\d+)\s*\]//i;

            chomp $create_args{'Subject'};

            warn "We're going to refer to ". $args{'Ticket'}->id;

        my ( $id, $txn_id, $msg ) = $ticket_as_user->Create(
            %create_args,
            Requestor => [ $args{'CurrentUser'}->EmailAddress],
            RefersTo => $args{'Ticket'}->id,
            Queue => $queue->id,
            MIMEObj => $args{'Message'}
        );
        unless ( $id ) {
            $msg = "Couldn't create ticket from message with commands, ".
                   "fallback to standard mailgate.\n\nError: $msg";
            $RT::Logger->error( $msg );

            return ($args{'CurrentUser'}, $args{'AuthLevel'});
        }



        # oow that we've created a ticket, we abort so we don't create another.
        $args{'Ticket'}->Load( $id );
        return ( $args{'CurrentUser'}, -2 );
    }
}


1;
