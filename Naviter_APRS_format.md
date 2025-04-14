---
title: OGNAVI APRS message specification
description: Naviter APRS message specification file, Copyright © 2025, Naviter d.o.o. All Rights Reserved
date: 2025-04-14
version: 1.0.2
---

# OGNAVI APRS message specification

Naviter’s APRS message format is built on top of the standard OGN-flavoured APRS
aircraft beacon messages.

## 1 Versions

In accordance with the OGN’s versioning schema, all sent messages will be versioned using
thedesttofield of the APRS message.

Format version consists of two parts:

1. 6 character long OGN-assigned identifier for Naviter: OGNAVI,
2. 1 character long format version

Thus, every version will be formatted asOGNAVI-<version>, for exampleOGNAVI-1.

**Note:** Thedesttofield _may_ be set toOGNAVI. This implies version 1.

### 1.1 Version history

**OGNAVI-1.0.2** FANET address type added (introduced 2025-04-14)

**OGNAVI-1** first version (introduced 2017-09-16)

## 2 Message format

### 2.1 OGNAVI-

Every message will begin with a header and will contain a comment as described below.

Header of each message will be formatted as specified in the original APRS message
specification:

<device_type><device_id>>OGNAVI,qAS,NAVITER:/<timestamp>h<latitude>
/<longitude>'<heading>/<ground_speed>/A=<altitude> <comment>.

Parameters:

**device_type** 3-character device type identifier (e.g.NAV,FLR, ...)
**device_id** 24-bit device identifier written in hexadecimal format. Device identifier is
only unique in the Naviter’s namespace (e.g. two devices using ids NAV000000 and
FLR000000 are not necessarily the same).
**timestamp** using the HMS format as specified in APRS 1.01 (e.g. 010203 means 01:02:
UTC).
**latitude** as specified in APRS 1.
**longitude** as specified in APRS 1.
**heading** as specified in OGN-flavoured APRS
**ground_speed** as specified in OGN-flavoured APRS
**altitude** as specified in OGN-flavoured APRS


**Note:** OGN-flavoured APRS specification states that if heading and ground speed are set
to 0 (i.e. the relevant part of the message is000/000), this indicates no data is provided
for either of the fields.

**Comment format**

Naviter tried to follow OGN’s comment format as closely as possible. Comments will be
formatted as follows:

!W<precision_enhancment>! id<identifier> +<climb_rate> <turn_rate>rot

Parameters:

**precision_enhancment** as specified in OGN-flavoured APRS
**identifier** 40-bit device identifier. See bellow for details.
**climb_rate** as specified in OGN-flavoured APRS
**turn_rate** as specified in OGN-flavoured APRS

**Device identifier**

Device identifier is a sequence of 40 bits encoded in a hexadecimal format (most significant
bit first) that tries to resemble OGN’s format as much as possible. It encodes (listed from
most to least significant bits):

- bit 0: stealth mode
- bit 1: do not track mode
- bits 2-5: aircraft type
- bits 6-11: address type (namespace is extended from 2 to 6 bits to avoid collisions
    with other tracking providers)
- bits 12-15: reserved for use at a later time
- bits 16-39: device id (24-bit device identifier, same as in APRS header)

**Note:** In OGN-flavoured APRS address types 00, 01, 10 and 11 are already used to
represent unknown, ICAO, FLARM and OGN devices (respectively).

For the extended address type Naviter is reserving the following ids:

**000000** unknown
**000001** ICAO
**000010** FLARM
**000011** OGN trackers
**000100** Naviter
**000101** FANET

Other address types might be added at a later time.


## 3 Examples

NAV042121>OGNAVI,qAS,NAVITER:/140648h4550.36N/01314.85E'090/152/A=
!W47! id0440042121 +000fpm +0.5rot
NAV04220E>OGNAVI,qAS,NAVITER:/140748h4552.27N/01155.61E'090/012/A=
!W81! id044004220E +060fpm +1.2rot
NAV07220E>OGNAVI,qAS,NAVITER:/125447h4557.77N/01220.19E'258/056/A=
!W76! id1C4007220E +180fpm +0.0rot

## 4 Other

### 4.1 Relaying messages from other devices

Naviter is able to relay position of a FLARM device connected to an Oudie through
it’s network. Origin of of such messages will beFLR<flarm_id>, notNAV<device_id>.
However, message will still be formatted usingOGNAVIschema.

Format of such messages will be:

<device_type><device_id>>OGNAVI,<relay_id>*,qAS,NAVITER:/<timestamp>h
<latitude>/<longitude>'<heading>/<ground_speed>/A=<altitude> <comment>.

Parameters:

All parameters – with the exception ofrelay_id– are the same as in the standard message
format described in section 2.

Therelay_idwill contain the identifier of the device that served as a relay. The identifier
will be formatted asNAV<device_id>, where device_idis a 6 character hexadecimal
number uniquely identifying an Oudie device.

The asterisk following therelay_idindicates that the transmision has been relayed.

**Example:**

FLRFFFFFF>OGNAVI,NAVABCDEF*,qAS,NAVITER:/092002h1000.00S/01000.00W'000/000/
A=003281 !W00! id2820FFFFFF +300fpm +1.7rot

## 5 Related documents

**APRS Protocol Reference, Protocol Version 1.0:** [http://www.aprs.org/doc/](http://www.aprs.org/doc/)
APRS101.PDF
**OGN-flavoured APRS:** https://github.com/svoop/ogn_client-ruby/wiki/OGN-
flavoured-APRS/c6678fecc15222cb980f491d09dfaba7e2982df