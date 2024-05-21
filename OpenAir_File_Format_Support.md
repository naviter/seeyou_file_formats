---
title: Extended OpenAir file format specification
description: SeeYou OpenAir specification with Naviter extensions, Copyright © 2024, Naviter d.o.o. All Rights Reserved
date: 2024-04-04
---

# SeeYou OpenAir file format support

*Version 1.0, Copyright © 2024, Naviter d.o.o. All Rights Reserved*

The OpenAir format, widely utilized in gliding, paragliding, and hang gliding applications, serves to disseminate airspace information and visualize it on maps. Originally developed by WinPilot in 1998, this format has since been embraced and extended by Naviter. This document outlines the OpenAir format alongside the extensions introduced by Naviter.

**General requirements:**

- **Encoding:** UTF-8
- **File Extension:** Use `.openair`, with  `.txt` as legacy alternative
- **Structure:** Text-based, with one command or data point per line
- **Comment Syntax:** Begins with `*` and extends to the end of the line.


## Units

### Geographic position

Geographic coordinates can be represented in two formats:

1. **Degrees, Minutes and Seconds (DMS) format:** `DD:MM:SS[N|S]` for latitude and `DDD:MM:SS[E|W]` for longitude.
   Example: `108:26:46W`
2. **Degrees and Decimal Minutes (DDM) format:**  `DD:MM.mmm[N|S]` for latitude and `DDD:MM.mmm[E|W]` for longitude.
   Example: `45:15.531N`

Use a consistant format for each command or data point, either DMS  `45:40:30N 014:18:20E` or DDM `45:40.500N 014:18.333E`.

### Altitude

Altitude is specified in feet `ft` (recommended) or in meters `m`. Example: `300ft` or `1500m`.

### Distance

Distance is measured in nautical miles `nm` and is implied, meaning it is specified <u>without a unit.</u>  This applies to definitions such as radii, widths and segments, see: [DA](#da:-define-an-arc-between-start-and-end-bearing), [DB](#db:-define-an-arc-between-start-and-end-point), [DY](#dy:-define-an-airway-segment), or [V](#v:-variable-assignment) for more.


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

| Class | Definition       |
| ----- | ---------------- |
| A     | Class A Airspace |
| B     | Class B Airspace |
| C     | Class C Airspace |
| D     | Class D Airspace |
| E     | Class E Airspace |
| F     | Class F Airspace |
| G     | Class G Airspace |

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

*Optional.*  Identifies the type of airspace or a special-use airspace. Typically used immediately after the `AC` command.

Format:
```
AY Type
```

The `Type` field accepts various categories or functions of the airspace: 

| Type | Description     |
| ---- | --------------- |
| AWY  | Airway                             |
| CTR  | Control Zone                       |
| GSEC | Glider Sector                      |
| MTMA | Militaty Terminal Manouvering Area |
| GP   | Gllider Prohibited Area            |
| P    | Prohibited Area                    |
| Q    | Danger Area                        |
| R    | Restricted Area                    |
| RMZ  | Radio Mandatory Zone               |
| TRA  | Temporary Reserved Area            |
| TMZ  | Transponder Mandatory Zone         |

Example:
```
AC E 
AY RMZ
```

#### AF: Airspace Frequency

*Optional.* Communication frequency of ATC station or authority overseeing the airspace - used by glider pilots for contanct.

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
AL 1000ft MSL
```

> [!IMPORTANT]
> Each airspace must have only one upper altitude limit. Including multiple altitude references creates ambiguity and is considered invalid (e.g., ~~`100m AGL/423m AMSL`~~ is not permitted).

#### AL: Lower Alitutde Limit

Defines the lowest boundary (the floor) of the airspace, including the altitude's reference point.

Format:
```
AL Altitude AltRef
```

Altitude references must be `AGL`, `FL`, `STD`, `MSL`. For areas extending to the ground, use `GND`, omitting the altitude.


Example:
```
AH FL145
AL 1000ft AGL
```

> [!IMPORTANT]
> Each airspace must have only one lower altitude limit. Including multiple altitude references creates ambiguity and is considered invalid (e.g., ~~`100m AGL/423m AMSL`~~ is not permitted).

#### Supported Altitude References

| AltRef | Description                                          |
| ------ | ---------------------------------------------------- |
| AGL    | ft Above Ground Level                                |
| FL     | Flight Level                                         |
| STD    | Standard Atmospheric Pressure                        |
| AMSL   | Above Mean Sea Level                                 |
| GND    | Ground, no altitude. **AL only, no numeric value**   |
| UNL    | Unlimited, no altitude **AH only, no numeric value** |


### D: Geometric Definitions

Geometric definition commands, often used with variable assignemnt `V`, define airspace geometry. Points are specified in degrees, minutes, seconds (DMS) or degrees and decimal minutes (DDM) notation. Radii are defined in nautical miles `nm` , with unit omitted.

#### DP: Polygon point

Polygons vertices are defined by a series of lines that start with `DP`. They are expected to be mapped clockwise and closed - last defined point is the same as the first . This is the recommended for outlining airspace geometry.

Format:
```
DP Point
```

Example: 
```
DP 53:47:06 N 008:21:41 E   
DP 53:50:58 N 008:55:25 E 
DP 53:45:08 N 008:57:21 E 
DP 53:41:10 N 008:23:38 E 
DP 53:47:06 N 008:21:41 E 

or

DP 53:47.100 N 008:21.700 E   
DP 53:50.960 N 008:55.825 E 
DP 53:45.800 N 008:57.211 E 
DP 53:41.755 N 008:23.890 E 
DP 53:47.100 N 008:21.700 E 
```
> [!IMPORTANT]
> Do not mix DMS and DDM notations. Stick to one definition throughout the file.

#### DA: Arc between start and end bearing

> [!NOTE]
>
> Combining airspace shapes defined with `DA`  arcs with points defined as `DP` can result in inconsistencies in how airspace is displayed. Avoid using `DA` if possible.

Defines an arc between two bearings, with its center set by a [V](#v:-variable-assignment) command before. The direction is clockwise by default, but can be altered with `V`.

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
> The arc is over-defined with `V` and `DB` sentences. Calculate the center of the arc carefully to avoid inconsistent display across various implementations on client software.

Defines an arc between two points, with its center set by a [V](#v:-variable-assignment) command before. The direction is clockwise by default, but can be altered with `V`.

Format:

```
DB Point 1, Point 2
```

Example:

```
V X=39:13:00N 118:13:00W
DB 39:36:40N 119:46:10W, 39:29:09N, 119:36:10W
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
V X=50:35:36 N 007:56:42 E
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
