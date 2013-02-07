# --
# Kernel/Output/HTML/CustomerUserGenericTicket.pm
# Copyright (C) 2001-2012 OTRS AG, http://otrs.org/
# --
# $Id: CustomerUserGenericTicket.pm,v 1.23 2012/11/20 14:56:45 mh Exp $
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::CustomerUserGenericTicket;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.23 $) [1];

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed objects
    for (
        qw(ConfigObject LogObject DBObject LayoutObject TicketObject MainObject EncodeObject UserID)
        )
    {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # don't show ticket search links in the print views
    if ( $Self->{LayoutObject}->{Action} =~ m{Print$}smx ) {
        return;
    }

    # lookup map
    my %Lookup = (
        Types => {
            Object => 'Kernel::System::Type',
            Return => 'TypeIDs',
            Input  => 'Type',
            Method => 'TypeLookup',
        },
        Queues => {
            Object => 'Kernel::System::Queue',
            Return => 'QueueIDs',
            Input  => 'Queue',
            Method => 'QueueLookup',
        },
        States => {
            Object => 'Kernel::System::State',
            Return => 'StateIDs',
            Input  => '',
            Method => '',
        },
        Priorities => {
            Object => 'Kernel::System::Priority',
            Return => 'PriorityIDs',
            Input  => 'Priority',
            Method => 'PriorityLookup',
        },
        Locks => {
            Object => 'Kernel::System::Lock',
            Return => 'LockIDs',
            Input  => 'Lock',
            Method => 'LockLookup',
        },
        Services => {
            Object => 'Kernel::System::Service',
            Return => 'ServiceIDs',
            Input  => 'Name',
            Method => 'ServiceLookup',
        },
        SLAs => {
            Object => 'Kernel::System::SLA',
            Return => 'SLAIDs',
            Input  => 'Name',
            Method => 'SLALookup',
        },
    );

    # get all attributes
    my %TicketSearch = ();
    my @Params = split /;/, $Param{Config}->{Attributes};
    for my $String (@Params) {
        next if !$String;
        my ( $Key, $Value ) = split /=/, $String;

        # do lookups
        if ( $Lookup{$Key} ) {
            next if !$Self->{MainObject}->Require( $Lookup{$Key}->{Object} );
            my $Object = $Lookup{$Key}->{Object}->new( %{$Self} );
            my $Method = $Lookup{$Key}->{Method};
            $Value = $Object->$Method( $Lookup{$Key}->{Input} => $Value );
            $Key = $Lookup{$Key}->{Return};
        }

        # build link and search attributes
        if ( $Key =~ /IDs$/ ) {
            if ( !$TicketSearch{$Key} ) {
                $TicketSearch{$Key} = [$Value];
            }
            else {
                push @{ $TicketSearch{$Key} }, $Value;
            }
        }
        elsif ( !defined $TicketSearch{$Key} ) {
            $TicketSearch{$Key} = $Value;
        }
        elsif ( !ref $TicketSearch{$Key} ) {
            my $ValueTmp = $TicketSearch{$Key};
            $TicketSearch{$Key} = [$ValueTmp];
        }
        else {
            push @{ $TicketSearch{$Key} }, $Value;
        }
    }

    # build url

    # note:
    # "special characters" in customer id have to be escaped, so that DB::QueryCondition works
    my $CustomerIDEscaped
        = $Self->{DBObject}->QueryStringEscape( QueryString => $Param{Data}->{UserCustomerID} );

    my $Action    = $Param{Config}->{Action};
    my $Subaction = $Param{Config}->{Subaction};
    my $URL       = $Self->{LayoutObject}->{Baselink} . "Action=$Action;Subaction=$Subaction";
    $URL .= ';CustomerID=' . $Self->{LayoutObject}->LinkEncode($CustomerIDEscaped);
    for my $Key ( sort keys %TicketSearch ) {
        if ( ref $TicketSearch{$Key} eq 'ARRAY' ) {
            for my $Value ( @{ $TicketSearch{$Key} } ) {
                $URL .= ';' . $Key . '=' . $Self->{LayoutObject}->LinkEncode($Value);
            }
        }
        else {
            $URL .= ';' . $Key . '=' . $Self->{LayoutObject}->LinkEncode( $TicketSearch{$Key} );
        }
    }

    if ( defined $Param{Config}->{CustomerUserLogin} && $Param{Config}->{CustomerUserLogin} ) {
        my $CustomerUserLoginEscaped = $Self->{DBObject}->QueryStringEscape(
            QueryString => $Param{Data}->{UserLogin},
        );

        $TicketSearch{CustomerUserLogin} = $CustomerUserLoginEscaped;
        $URL .= ';CustomerUserLogin='
            . $Self->{LayoutObject}->LinkEncode($CustomerUserLoginEscaped);
    }

    my $Count = $Self->{TicketObject}->TicketSearch(

        # result (required)
        %TicketSearch,
        CustomerID => $CustomerIDEscaped,
        CacheTTL   => 60 * 2,
        Result     => 'COUNT',
        Permission => 'ro',
        UserID     => $Self->{UserID},
    );

    my $CSSClass = $Param{Config}->{CSSClassNoOpenTicket};
    if ($Count) {
        $CSSClass = $Param{Config}->{CSSClassOpenTicket};
    }
    
# myh dob

    my @LastTicket = $Self->{TicketObject}->TicketSearch(
        Result => 'ARRAY',
        CacheTTL   => 60 * 2,
        Limit => 1,
        StateType => 'Closed',
        CustomerID => $CustomerIDEscaped,
        OrderBy => 'Down',
        SortBy  => 'Changed',   
        Permission => 'ro',
        UserID     => $Self->{UserID},
    );

    my %LCTicket = $Self->{TicketObject}->TicketGet(
        TicketID      => $LastTicket[0],
        DynamicFields => 0,         # Optional, default 0. To include the dynamic field values for this ticket on the return structure.
        Silent        => 0,         # Optional, default 0. To suppress the warning if the ticket does not exist.
    );
    
    my ($LClosed, $LCURLStart, $LCURLStop);

    if ($LastTicket[0]) {
        $LClosed      = $LCTicket{Changed};
        $LCURLStart   = '<a href="/otrs/index.pl?Action=AgentTicketZoom;TicketID=' . $LastTicket[0] . '"'
            . 'title="' . $LCTicket{Title} . '"'
            . '> '; 
        $LCURLStop    = '</a>';
    }
    else {
        $LClosed = 'none';
    }
# myh dob

    # generate block
    $Self->{LayoutObject}->Block(
        Name => 'CustomerItemRow',
        Data => {
            %{ $Param{Config} },
            CSSClass  => $CSSClass,
            Extension => " ($Count)",
            URL       => $URL,
# myh dob
            LastClosed=> $LClosed,
            LCURLStart=> $LCURLStart,
            LCURLStop=>  $LCURLStop,
# myh dob
        },
    );

    return 1;
}

1;
