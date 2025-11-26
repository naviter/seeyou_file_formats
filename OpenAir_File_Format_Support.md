---
title: Extended OpenAir file format specification
description: SeeYou OpenAir specification with Naviter extensions, Copyright © 2025, Naviter d.o.o. All Rights Reserved
date: 2025-11-25
version: 2.1.1
header: ${title} - Naviter d.o.o.
footer: Page ${pageNo} of ${pageCount}
---

# SeeYou OpenAir file format specification

*Copyright © 2025-11-25, Naviter d.o.o. All Rights Reserved. Version 2.1.1*

The OpenAir format, widely utilized in gliding, paragliding, and hang gliding applications, serves to disseminate airspace information and visualize it on maps. Originally developed by WinPilot in 1998, this format has since been embraced and extended by Naviter. This document outlines the OpenAir format alongside the extensions introduced by Naviter.

**General requirements:**

- **Encoding:** UTF-8
- **File Extension:** Use `.openair`, with  `.txt` as legacy alternative
- **Structure:** Text-based, with one command or data point per line
- **Comment Syntax:** Begins with `*` and extends to the end of the line.

**Command Reference**

| Command | Format | Description | Required | Link |
|---------|--------|-------------|----------|------|
| `*VERSION` | `*VERSION: 2.1` | OpenAir version number | Yes | [Header](#header) |
| `*WRITTEN_BY` | `*WRITTEN_BY: Name` | Author/application name | Yes | [Header](#header) |
| `AC` | `AC Class` | Airspace class (A-G, UNC) | Yes | [AC](#ac-airspace-class) |
| `AN` | `AN Name` | Airspace name | No | [AN](#an-airspace-name) |
| `AY` | `AY Type` | Airspace type (CTR, TMA, RMZ, etc.) | No | [AY](#ay-airspace-type) |
| `AF` | `AF Frequency` | Communication frequency | No | [AF](#af-airspace-frequency) |
| `AG` | `AG Station Name` | Controlling station name | No | [AG](#ag-station-name) |
| `AA` | `AA start/end` or `AA NONE` | Activation times (ISO8601 UTC) | No | [AA](#aa-airspace-activation-times) |
| `AX` | `AX Code` | Transponder code (4 digits) | No | [AX](#ax-transponder-code) |
| `AH` | `AH Altitude AltRef` or `AH UNL` | Upper altitude limit | No | [AH](#ah-upper-alitutde-limit) |
| `AL` | `AL Altitude AltRef` or `AL GND` | Lower altitude limit | No | [AL](#al-lower-alitutde-limit) |
| `DP` | `DP Point` | Polygon point (recommended) | No* | [DP](#dp-polygon-point) |
| `DA` | `DA Radius, Start, End` | Arc between bearings | No* | [DA](#da-arc-between-start-and-end-bearing) |
| `DB` | `DB Point1, Point2` | Arc between points | No* | [DB](#db-arc-between-start-and-end-point) |
| `DC` | `DC Radius` | Circular area | No* | [DC](#dc-circular-area) |
| `V` | `V Command=Value` | Variable assignment (X, D, W) | No* | [V](#v-variable-assignment) |

## Units

### Geographic position

Geographic coordinates can be represented in two formats:

1. **Degrees, Minutes and Seconds (DMS) format:** `DD:MM:SS[N|S]` for latitude and `DDD:MM:SS[E|W]` for longitude.
   Example: `108:26:46W`
2. **Degrees and Decimal Minutes (DDM) format:**  `DD:MM.mmm[N|S]` for latitude and `DDD:MM.mmm[E|W]` for longitude.
   Example: `45:15.531N`

Use a consistent format for each command or data point, either DMS  `45:40:30N 014:18:20E` or DDM `45:40.500N 014:18.333E`.

### Altitude

Altitude is specified in feet `ft` (recommended) or in meters `m`. Example: `300ft` or `1500m`.

### Distance

Distance is measured in nautical miles `nm` and is implied, meaning it is specified <u>without a unit.</u>  This applies to definitions such as radii, widths and segments, see: [DA](#da:-define-an-arc-between-start-and-end-bearing), [DB](#db:-define-an-arc-between-start-and-end-point), [DY](#dy:-define-an-airway-segment), or [V](#v:-variable-assignment) for more.

### Time

Time is specified using the [ISO8601](https://en.wikipedia.org/wiki/ISO_8601) format, use only UTC (Zulu) time.


## Header

Header **must** contain a comment with the following information:

* OpenAIR Version number: `*VERSION: 2.1`
* Author (App/Person) of  file: `*WRITTEN_BY: SeeYou`


## Airspace Definition

An airspace definition consists of a series of commands grouped into a block starting with `AC` and the rest of the 'A' commands. This is followed by the geometric definiton of the airpsace, which utilizes commands starting with `D` and/or `V`

> [!IMPORTANT]
> Each individual airspace definition must begin with the `AC` command.

### A: General Definitions

Commands beginning with `A` and define general attributes of an airspace.

#### AC: Airspace Class

Specifies airspace class exclusively. The use is refined from the original format, where it was used more broadly.

Format:
```
AC Class
```

Class Options:

| Class  | Definition       |
| ------ | ---------------- |
| A      | Class A Airspace |
| B      | Class B Airspace |
| C      | Class C Airspace |
| D      | Class D Airspace |
| E      | Class E Airspace |
| F      | Class F Airspace |
| G      | Class G Airspace |
| UNC    | Unclassified     |

Example:
```
AC D
```



#### AN: Airspace Name

Defines the airspace's name.

Format:
```
AN Name
```

Here `Name` is the designated name for the airspace. For example `CTR Muenchen`. Any UTF-8 character is allowed, but to avoid issues with some older systems that might not display special characters correctly, it's better to use simpler versions (for example, change `ü` to `ue`).

Example:
```
AN ED-R6 Brokdorf H24
```

#### AY: Airspace Type

Identifies the type of airspace or a special-use airspace. Typically used immediately after the `AC` command.

Format:
```
AY Type
```

The `Type` field accepts various categories or functions of the airspace:

| Type    | Description                                                |
| ------- | ---------------------------------------------------------- |
| ACCSEC  | Airspace providing communication frequency in remote areas |
| ADIZ    | Air Defence Ident Zone                                     |
| ALERT   | Alert Area                                                 |
| ASRA    | Aerial Sporting Or Recreational Activity                   |
| ATZ     | Aeordrome Traffic Zone                                     |
| AWY     | Airway                                                     |
| CTA     | Controlled Traffic Area                                    |
| CTR     | Control Zone                                               |
| CUSTOM  | Custom or user defined airspace                            |
| FIR     | Flight Information Region                                  |
| FIS     | Flight Information Service Sector                          |
| GSEC    | Gliding Sector                                             |
| HTZ     | Helicopter Traffic Zone                                    |
| LTA     | Lower Traffic Area (Allows VFR Traffic in CTA)             |
| MATZ    | Military Airport Traffic Zone                              |
| MTA     | Military Training Area                                     |
| MTR     | Military Training Route                                    |
| N       | NTOAM Affected Area                                        |
| NONE    | Airspace without type                                      |
| OFR     | Overflight Restriction                                     |
| P       | Prohibited Area                                            |
| Q       | Danger Area                                                |
| R       | Restricted Area                                            |
| RMZ     | Radio Mandatory Zone                                       |
| TFR     | Temporary Flight Restriction                               |
| TIA     | Traffic Information Area                                   |
| TIZ     | Traffic Information Zone                                   |
| TMA     | Terminal Manoeuvring Area                                  |
| TMZ     | Transponder Mandatory Zone                                 |
| TRA     | Temporary Reserved Area                                    |
| TRAFR   | TRA/TSA Feeding Route                                      |
| TRZ     | Transponder Recommended Zone                               |
| TSA     | Temporary Segregated Area                                  |
| UIR     | Upper Flight Information Region                            |
| UTA     | Upper Traffic Area (Allows VFR Traffic in CTA)             |
| VFRR    | Designated Route for VFR                                   |
| VFRSEC  | Visual Flying Rules Sector                                 |
| WARNING | Warning Area                                               |

Example:
```
AC E 
AY RMZ
```



#### AF: Airspace Frequency

*Optional.* Communication frequency of ATC station or authority overseeing the airspace - used by glider pilots for contact.

Format:
```
AF Frequency
```

Example:
```
AC E 
AY RMZ
AN RMZ ETMN-GLIDER HX 
AF 123.300
```



#### AG: Station Name

*Optional.* Name of the controlling station for the specified airspace - a name that a glider pilot would use in a radio call.

Format:
```
AG Station Name
```

Example:
```
AC E 
AY RMZ
AN RMZ ETMN-GLIDER HX 
AF 123.300
AG Nordholz Radar
```



#### AA: Airspace Activation Times
*Optional.* Use the ISO 8601 time interval format to specify when the airspace is active. The interval must use UTC (Zulu) time. Local time or time zone offsets are not supported.

To handle unknown or flexible activation times, use the NONE token:
* `AA start_time/end_time`: Defines a fixed activation interval.
* `AA start_time/NONE`: The airspace becomes active at start_time, and stays active until an unspecified end time.
* `AA NONE/end_time`: The airspace is active until end_time, with no known start time.
* `AA NONE`: No specific activation times are defined. The airspace is included in the data but only shown when activation times are later provided (e.g. by NOTAM). No other AA commands may follow — this overrides them all.

```
AA 2023-12-16T12:00Z/2023-12-16T13:00Z   ; Active from 12:00 to 13:00 UTC
AA 2024-12-17T00:00Z/2024-12-17T24:00Z   ; Active for the entire UTC day
AA 2024-12-17T00:00Z/NONE                ; Active from midnight UTC until unspecified end
AA NONE/2024-12-18T00:00Z                ; Active until midnight UTC, with unknown start
AA NONE                                  ; No defined time - inactive
```

#### AX: Transponder Code

*Optional* Transponder code to be used with the airspace. Must be a 4 digit code.

```
AX 7000
```


### A: Altitude Definitions

#### AH: Upper Alitutde Limit

Defines the highest boundary (the ceiling) of the airspace, including the altitude's reference point.

Format:
```
AH Altitude AltRef
```

Altitude references must be `AGL`, `FL`, `STD`, `AMSL` . For an undefined upper limit, use `UNL` without specifying an altitude.

Example:
```
AH FL145
AL 1000ft AMSL
```

> [!IMPORTANT]
> Each airspace definition must include only one upper altitude limit. Including multiple altitude references creates ambiguity and is considered invalid (e.g., ~~`100m AGL/423m AMSL`~~ is not permitted).

#### AL: Lower Alitutde Limit

Defines the lowest boundary (the floor) of the airspace, including the altitude's reference point.

Format:
```
AL Altitude AltRef
```

Altitude references are `AGL`, `FL`, `STD`, `AMSL`. For areas extending to the ground, use `GND`, omitting the altitude.


Example:
```
AH FL145
AL 1000ft AGL
```

> [!IMPORTANT]
> Each airspace definition must include only one lower altitude limit. Including multiple altitude references creates ambiguity and is considered invalid (e.g., ~~`100m AGL/423m AMSL`~~ is not permitted).

#### Supported Altitude References

| AltRef | Description                                          |
| ------ | ---------------------------------------------------- |
| AGL    | Above Ground Level                                   |
| FL     | Flight Level                                         |
| STD    | Standard Atmospheric Pressure                        |
| AMSL   | Above Mean Sea Level                                 |
| GND    | Ground, no altitude. **AL only, no numeric value**   |
| UNL    | Unlimited, no altitude **AH only, no numeric value** |


### D: Geometric Definitions

Geometric definition commands, often used with variable assignemnt `V`, define airspace geometry. Points are specified in degrees, minutes, seconds (DMS) or degrees and decimal minutes (DDM) notation. Radii are defined in nautical miles `nm` , with unit omitted.

#### DP: Polygon point

Polygon vertices are defined by a series of lines that start with `DP`. They are expected to be mapped clockwise and closed - last defined point is the same as the first . This is the recommended method for outlining airspace geometry.

Format:
```
DP Point
```

Example: 
```
DP 53:47:06N 008:21:41E   
DP 53:50:58N 008:55:25E 
DP 53:45:08N 008:57:21E 
DP 53:41:10N 008:23:38E 
DP 53:47:06N 008:21:41E 

or

DP 53:47.100N 008:21.700E   
DP 53:50.960N 008:55.825E 
DP 53:45.800N 008:57.211E 
DP 53:41.755N 008:23.890E 
DP 53:47.100N 008:21.700E 
```
> [!IMPORTANT]
> Do not mix DMS and DDM notations. Stick to one definition throughout the file.

#### DA: Arc between start and end bearing

> [!NOTE]
>
> Combining airspace shapes defined with `DA`  arcs with points defined as `DP` can result in inconsistencies in how airspace is displayed. Avoid using `DA` if possible.

Defines an arc between two bearings, with its center set by a preceding [V](#v:-variable-assignment) command. The direction is clockwise by default, but can be altered with `V`.

Format:
```
DA Radius, Start Angle, End Angle
```

Example:
```
V X=39:13:00N 118:13:00W
DA 10, 270, 290
```

#### DB: Arc between start and end point

> [!NOTE]
>
> The arc is overdefined with `V` and `DB` sentences. Calculate the center of the arc carefully to avoid inconsistent display across various implementations on client software.

Defines an arc between two points, with its center set by a preceding [V](#v:-variable-assignment) command. The direction is clockwise by default, but can be altered with `V`.

Format:

```
DB Point 1, Point 2
```

Example:

```
V X=39:13:00N 118:13:00W
DB 39:36:40N 119:46:10W, 39:29:09N 119:36:10W
```

#### DC: Circular area

Defines a circular area centered on a point set by a preceding [V](#v:-variable-assignment) command. The radius is given in nautical miles.

Format:
```
DC Radius
```

Example:
```
AC Q
AN PARA Ailertchen EDGA
AH FL100
AL GND
V X=50:35:36N 007:56:42E
DC 2.00
```

#### DY: Airway segment

> [!NOTE]
>
> Although DY is part of the original WinPilot definition, we advise against using the `DY` type. It doesn't stitch well in a string of airways. Use `DP` instead to define airways more accurately.

### V: Variable Assignment

This command sets up parameters for geometric definitions in `DA`, `DB`, `DC`, and `DY` commands, and must be declared beforehand.

Format:

```
V Command=Value
```

Comand and Value options:

| Command | Value      | Description                                                  |
| ------- | ---------- | ------------------------------------------------------------ |
| D       | `+` or `-` | Sets the direction for `DA`and `DB`records. `+` is clockwise direction, which is also a default. |
| X       | Point      | Sets the center of the `DA`, `DB`and `DC` records.           |
| W       | Number     | Sets the width of an airway in `nm`                          |

Example:

```
V X=39:29.9N 119:46.1W
DA 7,290,320
DA 10,270,290
DA 10,320,200
V D=-
DA 5,200,270
```
