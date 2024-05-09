---
title: SeeYou CUB file format
description: SeeYou CUB file format specification file, Copyright © 2024, Naviter d.o.o. All Rights Reserved
date: 2024-05-08
---

# SeeYou CUB File Format 

*Copyright © 2024, Naviter d.o.o. All Rights Reserved*

The CUB file format is designed to store airspace data that is displayed and utilized by flight navigation software from Naviter and LX Nav.

This format is structured as a binary file comprising three distinct parts: each file begins with a `CubHeader`, followed by a list of `CubItem's`. Each `CubItem` represents a single airspace, detailing its properties and linking to `CubPoint's`, which are cataloged in the final section of the file.

- Format: Binary
- File Extension: `.cub`



## CubHeader

The ` CubHeader` is the initial segment of the CUB file format, spanning the first 210 bytes. It contains metadata about the file and defines how the data should be interpreted, most notably speciffying the byte offsets for `CubItem` and `CupPoint` segments.

Byte ordering is defined by `PcByteOrder` for integer data, float data is always LE.

Coordinates data is in radians.


| Bytes | Data Type | Name             | Description                                                  |
| ----- | --------- | ---------------- | ------------------------------------------------------------ |
| 4     | UINT32    | `Ident`          | File Identifier, must be `0x425543C2`, LE                    |
| 112   | CHAR[112] | `Title`          | Copyright notice.                                            |
| 16    | UNIT16[8] | `AllowedSerials` | List of  up to 8 device serial numbers authorized to access the file; set to `0` otherwise. Used only when `IsSecured` equals `2`, LE. |
| 1     | UNIT8     | `PcByteOrder`    | Byte ordering flag; BE if set to `0`, LE otherwise.          |
| 1     | UNIT8     | `IsSecured`      | Encryption status for data follwoing the header; `0` for no encryption. |
| 4     | UINT32    | `Crc32`          | Reserved for future use (currently ignored).                 |
| 164   | UINT8[16] | `Key`            | Encription key, used if `IsSecured`is not `0`                |
| 4     | INT32     | `SizeOfItem`     | Size of single `CubItem`.                                    |
| 4     | INT32     | `SizeOfPoint`    | Size of single `CubPoint`.                                   |
| 4     | INT32     | `HdrItems`       | Number of `CubItem's` contained in the file.                 |
| 4     | INT32     | `MaxPts`         | Maximal number of points per `CubItem`.                      |
| 4     | FLOAT     | `Left`           | Left value of data bounding box.                             |
| 4     | FLOAT     | `Top`            | Top value of data bounding box.                              |
| 4     | FLOAT     | `Right`          | Right value of data bounding box.                            |
| 4     | FLOAT     | `Bottom`         | Bottom value of data bounding box.                           |
| 4     | FLOAT     | `MaxWidth`       | Maximum width of any `CubItem`.                              |
| 4     | FLOAT     | `MaxHeight`      | Maximum height of any `CubItem`.                             |
| 4     | FLOAT     | `LoLaScale`      | Scaling factor used in shape construction.                   |
| 4     | INT32     | `HeaderOffset`   | Byte offset to the first `CubItem`.                          |
| 4     | INT32     | `DataOffset`     | Byte offset to the first `CubPoint`.                         |
| 4     | INT32     | `Alignment`      | Reserved for future use (currently ignored).                 |



## CubItem

The `CubItem` structure stores essential information about each airspace or NOTAM-defined airspace. Information regarding their storage is detailed in the header. The first `CubItem` is located at the `HeaderOffset` specified in the `CubHeader`, and the file contains a total of `HdrItems` items. Each item occupies `SizeOfItem` bytes, and each subsequent `CubItem` is located immediately following the previous one.

If the `SizeOfItem` is smaller than the total size of the `CubItem` structure (42 bytes), the remaining bytes should be set to 0.

| Bytes | Data Type | Name           | Description                                                  |
| ----- | --------- | -------------- | ------------------------------------------------------------ |
| 4     | FLOAT     | `Left`         | Left boundary of the item's bounding box.                    |
| 4     | FLOAT     | `Top`          | Top boundary of the item's bounding box.                     |
| 4     | FLOAT     | `Right`        | Right boundary of the item's bounding box.                   |
| 4     | FLOAT     | `Bottom`       | Bottom boundary of the item's bounding box.                  |
| 1     | UINT8     | `Style`        | Airspace type; combines highest bit and lowest 4 bits to form `CubStyle`, bits 5-7 represent `CubClass`. |
| 1     | UINT8     | `AltStyle`     | Altitude style for `MinAlt` (lowest 4 bits) and `MaxAlt` (highest 4 bits). |
| 2     | INT16     | `MinAlt`       | Minimum altitude of the airspace (in meters).                |
| 2     | INT16     | `MaxAlt`       | Maximum altitude of the airspace (in meters).                |
| 4     | INT32     | `PointsOffset` | Relative byte offset to the first `CubPoint` associated with this airspace from the beginning of the CubPoint's segment. |
| 4     | INT32     | `TimeOut`      | Timeout for this airspace (not used).                        |
| 4     | UINT32    | `ExtraData`    | Field reserved for additional data.                          |
| 8     | UINT64    | `ActiveTime`   | Encoded active time for NOTAMs affecting this airspace.      |



### CubStyle Mappings

`CubStyle` categorizes the airspace style.

| Value | Description   |
| ----- | ------------- |
| 0x00  | Unknown Style |
| 0x01  | ctr           |
| 0x02  | rarea         |
| 0x03  | parea         |
| 0x04  | darea         |
| 0x05  | tra           |
| 0x06  | tma           |
| 0x07  | tiz           |
| 0x08  | awy           |
| 0x09  | cta           |
| 0x0a  | gliderSec     |
| 0x0b  | tmz           |
| 0x0c  | matz          |
| 0x0d  | rmz           |
| 0x0f  | notam         |
| 0x80  | advisoryArea  |
| 0x81  | airDefIdZone  |
| 0x82  | flInfoRegion  |
| 0x83  | delegatedFIR  |
| 0x84  | trafficInfoArea |
| 0x85  | specialRulesZone |
| 0x86  | tempFlightRestriction |
| 0x87  | aerodromeTrafficZone |
| 0x88  | flInfoServiceArea |
| 0x89  | rmz           |
| 0x8a  | aerialSportAndRecreatArea |
| 0x8b  | transponderRecommendedZone |
| 0x8c  | vfrRoute      |
| 0x8d  | alert         |
| 0x8e  | tempReserved  |
| 0x8f  | warning       |



### CubClass Mappings

`CubClass` categorizes the airspace class.

| Value | Description   |
| ----- | ------------- |
| 0     | Unknown Class |
| 1     | Class A       |
| 2     | Class B       |
| 3     | Class C       |
| 4     | Class D       |
| 5     | Class E       |
| 6     | Class F       |
| 7     | Class G       |



### AltStyle Mappings

`AltStyle` specifies the reference used for determining the altitude boundaries (both upper and lower) of an airspace.

| Value | Description               |
| ----- | ------------------------- |
| 0     | Unknown                   |
| 1     | AGL (Above Ground Level)  |
| 2     | MSL (Mean Sea Level)      |
| 3     | FL (Flight Level)         |
| 4     | Unlimited                 |
| 5     | Altitude defined by NOTAM |



### Extra Data

The `Extra Data` field encodes specific NOTAM data when the last two bits are set to 0. Below is a breakdown of how this data is structured within the field:

| Bits  | Description                   | Values                                                       |
| ----- | ----------------------------- | ------------------------------------------------------------ |
| 30-31 | Reserved                      | `00` indicates NOTAM data encoding                           |
| 28-29 | NOTAM Type                    | `0`: None<br />`1`: Cancel<br />`2`: New<br />`3`: Replace   |
| 23-27 | First Letter of NOTAM Subject | Encoded as 1 (A) to 26 (Z)[^fn1]                             |
| 18-22 | Last Letter of NOTAM Subject  | Encoded as 1 (A) to 26 (Z)[^fn1]                             |
| 13-17 | First Letter of NOTAM Action  | Encoded as 1 (A) to 26 (Z)[^fn1]                             |
| 8-12  | Last Letter of NOTAM Action   | Encoded as 1 (A) to 26 (Z)[^fn1]                             |
| 4-6   | NOTAM Traffic                 | `0`: Miscelaneous<br />`1`: IFR<br />`2`: VFR<br />`3`: IFR & VFR<br />`4`: Checklist |
| 0-3   | NOTAM Scope                   | `0`: Unknown<br />`1`: Aerodrome<br />`2`: En-route<br />`3`: Aerodrome and En-route<br />`4`: Nav. Warnig<br />`5`: Aerodrome and Nav Warning, `8`: Checklist |

[^fn1]: Letters are uppercase ASCII characters. They are encoded as integers, where 1 corresponds to 'A' and 26 corresponds to 'Z'.

### ActiveTime

| Bits  | Description               |
| ----- | ------------------------- |
| 63-52 | Days Active Flags.        |
| 26-51 | Encoded NOTAM Start Date. |
| 0-25  | Encoded NOTAM End Date.   |

#### Days Active Flags mapping

| Flag Value | Description             |
| ---------- | ----------------------- |
| 0x001      | Sunday                  |
| 0x002      | Monday                  |
| 0x004      | Tuesday                 |
| 0x008      | Wednesday               |
| 0x010      | Thursday                |
| 0x020      | Friday                  |
| 0x040      | Saturday                |
| 0x080      | Holidays                |
| 0x100      | AUP (Airspace Use Plan) |
| 0x200      | Irregular               |
| 0x400      | By NOTAM                |
| 0x800      | Not Set                 |

#### Unpacking NOTAM Time

NOTAM time is encoded in minutes within the `Active Time` field and is used for both `CubItem ActiveTime` and `CubPoint cdiInserted` type. To unpack this time into a more readable format:

1. **Minutes**: Extract the minutes from the total time using modulo 60. Subtract these minutes from the total time, then divide by 60.
2. **Hours**: Extract the hours from the remaining time using modulo 24. Subtract these hours, then divide by 24.
3. **Days**: Extract the day from the remaining time using modulo 31, add 1 to shift from zero-based to a one-based count, subtract the days, then divide by 31.
4. **Months**: Extract the month from the remaining time using modulo 12, add 1 to shift from zero-based to a one-based count, subtract the months, then divide by 12.
5. **Years**: Add 2000 to the remaining quotient to calculate the year.

This method translates encoded minutes into a full date and time format, allowing for easier interpretation and use of the data.

```C
minutes = time%60; time /= 60; 
hours = time%24; time /= 24;
days = (time%31) + 1; time /= 31;
months = (time%12) + 1; time /= 12;
years = time+2000;
```

## CubPoint

`CubPoint` encodes information about the shape, name, frequency, and other optional attributes of an airspace. The structure is 5 bytes long, with the first byte serving as a flag that determines how the remaining bytes are interpreted:

| 1st Byte | 2-4th Bytes                    |
| -------- | ------------------------------ |
| Flag     | Values, depending on the flag. |

### Set a New Origin

Flag `0x81` sets a new origin for subsequent points

| Bytes | Type  | Name | Description                             |
| ----- | ----- | ---- | --------------------------------------- |
| 1     | UINT8 | flag | 0x81                                    |
| 2     | INT16 | x    | Set new origin X-axis (`x * LoLaScale`) |
| 2     | INT16 | y    | Set new origin Y-axis (`y * LoLaScale`) |

### Add a New Point

Flag `0x01`adds a new point relative to the current origin:

| Bytes | Type  | Name | Description                                        |
| ----- | ----- | ---- | -------------------------------------------------- |
| 1     | UINT8 | flag | 0x01                                               |
| 2     | INT16 | x    | New point X-coordinate (`originX + x * LoLaScale`) |
| 2     | INT16 | y    | New point Y-coordinate (`originY + y * LoLaScale`) |

### Add Airspace Name

The first `CubPoint` with the 7th bit of the flag set to 1 indicates the start of the airspace name encoding. The lower 6 bits of the flag represent the length of the name (up to 64 characters).

| Bytes | Type  | Name | Description                                                  |
| ----- | ----- | ---- | ------------------------------------------------------------ |
| 1     | UINT8 | flag | `0x40 + Length`. For example name of length 20 (`0x14`), would result in in flag `0x54` |
| 4     |       | name | Airspace name                                                |

### Add Airspace Frequency

Following the airspace name, the frequency and its associated name are stored:

| Bytes | Type   | Name | Description        |
| ----- | ------ | ---- | ------------------ |
| 1     | UINT8  | flag | 0xC0               |
| 4     | UINT32 | freq | Airspace frequency |

### Add Frequency Name

Length of name is encoded in lowest 6 bits. String is located right after the structure.

| Bytes | Type  | Name | Description                                                  |
| ----- | ----- | ---- | ------------------------------------------------------------ |
| 1     | UINT8 | flag | `0x40 + Length`. For example name of length 20 (`0x14`), would result in in flag `0x54` |
| 4     |       | name | Frequency name                                               |

### Optional Data

The last optional part of data is interpreted byte by byte based on the second byte named `CubDataId`, which maps to different types of additional data:

| Bytes | Type  | Name      | Description                               |
| ----- | ----- | --------- | ----------------------------------------- |
| 1     | UINT8 | flag      | 0xA0                                      |
| 1     | UINT8 | CubDataId | Determines the type of the following data |
| 1     | UINT8 | b1        | Varies based on `CubDataId`               |
| 1     | UINT8 | b2        | Varies based on `CubDataId`               |
| 1     | UINT8 | b3        | Varies based on `CubDataId`               |

### Data ID Mappings

Different `CubDataId` values indicate specific types of data that follow the `CubPoint` structure:

| Value | Description                       | Details                                                      |
| ----- | --------------------------------- | ------------------------------------------------------------ |
| 0     | ICAO Code of the airport          | `b3` indicates the length of the following string            |
| 1     | Secondary Frequency               | `b1`, `b2`, `b3` represent the frequency                     |
| 2     | Exception rules to airspace class | `b2` and `b3` define the length of the subsequent string     |
| 3     | NOTAM Remarks                     | `b2` and `b3` define the length of the subsequent string     |
| 4     | NOTAM ID String                   | `b3` indicates the length of the subsequent string           |
| 5     | NOTAM Insert date and time        | Comprised of `b1`, `b2`, `b3`, and an additional byte after the structure |

When integers are composed from multiple bytes, they are always ordered from highest to lowest byte.
