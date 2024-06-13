---
title: SeeYou CUP file format 
description: SeeYou CUP file format specification file, Copyright © 2024, Naviter d.o.o. All Rights Reserved
date: 2024-05-08
---

# SeeYou CUP File Format

*Copyright © 2024, Naviter d.o.o. All Rights Reserved, Version 1.2*

SeeYou CUP Waypoint format is a simple comma separated text file. The extension is .CUP

It consists of two parts:

- Waypoints
- Tasks

The character formatting of the file is `UTF-8` or `Windows-1252` (legacy).

## Format of Waypoint Records

Each line represents one waypoint with the fields: Name, Code, Country, Latitude, Longitude,  Elevation, Style, Runway Direction, Runway Length, Runway width, Airport Frequency, Description, User data and Pictures.

Sample fields header:

`name,code,country,lat,lon,elev,style,rwdir,rwlen,rwwidth,freq,desc,userdata,pics` is contained at line number 1.

Here are a few examples:

- Waypoint:
  `"Cross Hands","CSS",UK,5147.809N,00405.003W,525ft,1,,,,"Turn Point, A48/A476, Between Cross Hands and Gorslas, 9 NMl ESE of Camarthen."`

- Airport:
  `"Lesce","LJBL",SI,4621.379N,01410.467E,504.0m,5,144,1130.0m,,123.500,"Home Airfield"`

- Outlanding:

  `"Aiton","O23L",FR,4533.517N,00614.050E,299.9m,3,110,300.0m,,"Page 222: O23L Large flat area. High crops. Sudden wind changes. Power lines N/S. S of road marked fields"`

Columns after style field may be missing and can be removed from header and data. For instance file that does not contain any userdata or pics can be as follows:

`name,code,country,lat,lon,elev,style,rwdir,rwlen,rwwidth,freq,desc`

The order of the columns is arbitrary, this is a valid header line:

`
lat,lon,elev,name,code,country,style,rwdir,rwlen,rwwidth,freq,desc
`

Fields containing a comma must be embraced in double quotes ("). Fields containing elevation or distance may have a unit suffix. If unit suffix is missing, meter is used as a unit.

### 1 - Waypoint Name

key name: `name`

This field contains the long name of the waypoint. This must be unique and can not be left empty.

Example: "Lesce"

### 2 - Code

key: `code`

This field contains the code or the short name for the waypoint. It is used to make finding a waypoint in a gliding instrument easier. We however do not specify the max. length.

Example: "LJBL"

### 3 - Country

key: `country`

Country IANA Top level domain standard is used for the country codes. A complete list is available at <https://www.iana.org/domains/root/db> and a helpful wiki article can be found <https://en.wikipedia.org/wiki/List_of_Internet_top-level_domains#Country_code_top-level_domains>

Example: SI

### 4 - Latitude

key: `lat`

Latitude is a field of length 9, where 1-2 characters are degrees, 3-4 characters are minutes, 5 decimal point, 6-8 characters are decimal minutes and 9th character is either N or S. The ellipsoid used is WGS-1984

|  Char 0  |  Char 1  |  Char 2   |  Char 3   | Char 4 |    Char 5    |    Char 6    |    Char 7    | Char 8 |
| :------: | :------: | :-------: | :-------: | :----: | :----------: | :----------: | :----------: | :----: |
|    5     |    1     |     0     |     7     |   .    |      8       |      3       |      0       | N \| S |
| $10^1$ ° | $10^0$ ° | $10^1$ \' | $10^0$ \' |   .    | $10^{-1}$ \' | $10^{-2}$ \' | $10^{-3}$ \' |        |

Example: SeeYou 5107.830N  is equal to 51° 07.830' N

### 5 - Longitude

key: `lon`

Latitude It is a field of length 10, where 1-2 characters are degrees, 3-4 characters are minutes, 5 decimal point, 6-8 characters are decimal minutes and 9th character is either N or S. The ellipsoid used is WGS-1984

|  Char 0  |  Char 1  |  Char 2  |  Char 3   |  Char 4   | Char 5 |    Char 6    |    Char 7    |    Char 8    | Char 9 |
| :------: | :------: | :------: | :-------: | :-------: | :----: | :----------: | :----------: | :----------: | :----: |
|    0     |    1     |    4     |     1     |     0     |   .    |      4       |      6       |      7       | E \| W |
| $10^2$ ° | $10^1$ ° | $10^0$ ° | $10^1$ \' | $10^0$ \' |   .    | $10^{-1}$ \' | $10^{-2}$ \' | $10^{-3}$ \' |        |

Example: SeeYou 01410.467E is equal to 014° 10.467' E

### 6 - Elevation

key: `elev`

Number with an attached unit. Unit can be either "m" for meters or "ft" for feet. Decimal separator must be a point. Mix of the units is allowed in the file.

Example: 504.0m

### 7 - Waypoint Style

key: `style`

Waypoint style describes the type of the waypoint. If a value other than the ones listed below is found in the file the parser should default it to 0.  Following digits represent these styles:

| Digit | Value                              |
| ----- | ---------------------------------- |
| 0     | Unknown                            |
| 1     | Waypoint                           |
| 2     | Airfield with grass surface runway |
| 3     | Outlanding                         |
| 4     | Gliding airfield                   |
| 5     | Airfield with solid surface runway |
| 6     | Mountain Pass                      |
| 7     | Mountain Top                       |
| 8     | Transmitter Mast                   |
| 9     | VOR                                |
| 10    | NDB                                |
| 11    | Cooling Tower                      |
| 12    | Dam                                |
| 13    | Tunnel                             |
| 14    | Bridge                             |
| 15    | Power Plant                        |
| 16    | Castle                             |
| 17    | Intersection                       |
| 18    | Marker                             |
| 19    | Control/Reporting Point            |
| 20    | PG Take Off                        |
| 21    | PG Landing Zone                    |

Example: 5

### 8 Runway Direction

key: `rwdir`

Three field string containing  the heading of the runway in degrees. For PG waypoint styles, the runway direction declares  mid direction of the first take off sector.

| Char 1 | Char 2 | Char 3 |
| :----: | :----: | :----: |
|  0-3   |  0-9   |  0-9   |

Example: 070

### 9 Runway Length

key: `rwlen`

Number with unit representing length of the runway. Only used with Waypoint style types 2, 3, 4 and 5. The unit can be either "m" for meters "nm" for nautical miles "ml" for statute miles. Decimal separator must be a point.

Example: 540.3m

### 10 Runway Width

Key: `rwwidth`

Number with unit representing length of the runway. Only used with Waypoint style types 2, 3, 4 and 5. The unit can be either "m" for meters "nm" for nautical miles "ml" for statute miles. Decimal separator must be a point.

Example: 540.3m

### 11 Airport Frequency

key: `freq`

Number field representing the frequency of the airport of length 7. Decimal separator must be a point. It can also be embraced in double quotes: <https://en.wikipedia.org/wiki/Airband> and is used only in connection with waypoint styles 2, 3, 4, 5.

| Char 0 | Char 1 | Char 2 | Char 3 | Char 4 | Char 5 | Char 6 |
| ------ | ------ | ------ | ------ | ------ | ------ | ------ |
| 1      | 1-3    | 0-9    | .      | 0-9    | 0-9    | 0 \| 5 |

Example: 122.355

### 12 Description

key: `desc`

It is a string field with no limitation in length where anything can be stored in.

### 13 Userdata

key: `userdata`

It is a string field with no limitation in length where anything can be stored in.

### 14 pics

key: `pics`

A string field containing the filename(s) of an JPG image stored in `pics/` folder of a seperate `pics.zip` file. See *SeeYou CUPX file format* specification. Multiple filenames must be separated by semicolon `;`  and string must be embraced in double quotes.

## Format of Task Record

Tasks part of the CUP file is divided from the Waypoints by including

`-----Related Tasks-----`

line.

Each Task is presented with comma separated task points in one line. Here are two examples:

- With description, options and observation zones:
  
  `"1000km FAI Triangle","0LESCE","Sv Peter","1K MAIER","1K ZELTW","1K UDBIN","Sv Peter","0LESCE" Options,NoStart=12:34:56,TaskTime=01:45:12,WpDis=False,NearDis=0.7km,NearAlt=300.0m ObsZone=0,Style=2,R1=400m,A1=180,Line=1 ObsZone=1,Style=0,R1=35000m,A1=30,R2=12000m,A2=12,A12=123.4 ObsZone=2,Style=3,R1=2000m,A1=180,Line=1`

- Without description, no options and observation zones:
  
  `,"0LESCE","0Start","750 Huje","750 Brenner","750 Gahns","0Start","0LESCE",`

The format is:

`description, takeoff, 1 turnpoint, 2 turnpoint, ..... , last turnpoint, landing`

Number of points in the task and number of tasks is not limited.

### Description

First column is the description of the task. The field is optional. If left empty SeeYou will determine the task type on runtime.

### Turnpoints

All successive columns, separated by commas Each column represents one waypoint name. The waypoint name must match the name field of one waypoint listed above the `----Related Tasks----` line.

Alternative point definition (when task point is not defined as waypoint):

`Point=1,"Point_3",PNT_3,,4627.136N,01412.856E,0.0m,1,,,,,,,`

This defines first turnpoint (after takeoff). Format must be the same as for the waypoint definitions.

### Options and Observation Zones

The line with the definition of the description and the list of task points is followed by "Task Options" line, this line is successively followed by "Observation Zone" lines for the turn points specified in the task above. Note that if any of the data is missing, default settings will be used instead. Here an example:

```
Options,NoStart=12:34:56,TaskTime=01:45:12,WpDis=False,NearDis=0.7km,NearAlt=300.0m
ObsZone=0,Style=2,R1=400m,A1=180,Line=1
ObsZone=1,Style=0,R1=35000m,A1=30,R2=12000m,A2=12,A12=123.4
ObsZone=2,Style=3,R1=2000m,A1=180,Line=1
```

Options line must start with "Options" keyword.

#### Possible Values in Options Line

- `NoStart`
  Opening of start line

- `TaskTime`
  Designated Time for the task

- `WpDis`
  Task distance calculation. False = use fixes, True = use waypoints for the distance calculation

- `NearDis`
  Distance tolerance

- `NearAlt`
  Altitude tolerance

- `MinDis`
  Uncompleted leg. False = calculate maximum distance from last observation zone.

- `RandomOrder`
  If true, then the random order of waypoints is checked

- `MaxPts`
  Maximum number of points

- `BeforePts`
  Number of mandatory waypoints at the beginning.
  - 1: start line only
  - 2: start line plus first point in task sequence (Task line).
  
- `AfterPts`
  Number of mandatory waypoints at the end.
  - 1: finish line only
  - 2: finish line and one point before finish in task sequence (Task line)
  
- `Bonus`
  Bonus for crossing the finish line Observation zone line must start with "ObsZone" keyword.

#### Possible Values in Observation Zone Line

- `ObsZone`
  Consecutive number of a waypoint (0 = Start)
- `Style`
  Observation Zone Direction
  - 0 - Fixed value
  - 1 - Symmetrical
  - 2 - To next point
  - 3 - To previous point
  - 4 - To start point
- `R1`
  Radius 1
- `A1`
  Angle 1 in degrees
- `R2`
  Radius 2
- `A2`
  Angle 2 in degrees
- `A12`
  Angle 12

### Multiple Starts

A sample line defining multiple task starts:
`STARTS=Celovec,Hodos,Ratitovec,Jamnik`

Waypoints must be defined, observation zones are the same for all possible starts.
