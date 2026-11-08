---
title: SeeYou CUPX file format description 
description: SeeYou CUP file format specification file, Copyright © 2021, Naviter d.o.o. Licensed under the MIT License
date: 2025-10-07
version: 2.4.0
header: ${title} - Naviter d.o.o.
footer: Page ${pageNo} of ${pageCount}
---

# SeeYou CUPX file format

*Copyright © 2025-10-07, Naviter d.o.o. Licensed under the [MIT License](LICENSE). Version 2.4.0*



CUPX format is an extension of the cup format. It is actually a combination of two ZIP files combined in a CUPX file.

It can be created by

`copy /b pics.zip + points.zip test.cupx`

or on linux

`cat pics.zip points.zip > test.cupx`

The first ZIP file (pics.zip) contains all the images in JPG format in the `pics/` folder. 

The second ZIP file (points.zip) contains POINTS.CUP that cointains the waypoints with filenames of pictures corresponding to points in the `pics` column of the CUP file (without folder name).

## License

Copyright © Naviter d.o.o.

This specification is licensed under the [MIT License](LICENSE). You can use, copy, change and distribute it, also in commercial software. You must keep the copyright notice and the license text.
