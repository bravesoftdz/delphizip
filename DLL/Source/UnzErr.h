
/* 

  Copyright (c) 1990-2007 Info-ZIP.  All rights reserved.

  See the accompanying file LICENSE, version 2007-Mar-4 or later
  (the contents of which are also included in zip.h) for terms of use.
  If, for some reason, all these files are missing, the Info-ZIP license
  also may be found at:  ftp://ftp.info-zip.org/pub/infozip/license.html

  parts Copyright (C) 1997 Mike White, Eric W. Engler
************************************************************************
 Copyright (C) 2009, 2010  by Russell J. Peters, Roger Aelbrecht

   This file is part of TZipMaster Version 1.9.

    TZipMaster is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    TZipMaster is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public License
    along with TZipMaster.  If not, see <http://www.gnu.org/licenses/>.

    contact: problems@delphizip.org (include ZipMaster in the subject).
    updates: http://www.delphizip.org
    DelphiZip maillist subscribe at http://www.freelists.org/list/delphizip 
************************************************************************/

#ifndef __UNZERR
#define __UNZERR
/*
#ifdef NO_CONSTS
const char CentSigMsg[]  =
  "error:  expected central file header signature not found (file #%u).\n";
const char EndSigMsg[]  =
  "\nnote: didn't find end-of-central-dir signature at end of central dir.\n";
const char SeekMsg[]  =
  "error [%s]:  attempt to seek before beginning of zipfile\n%s";
const char FilenameNotMatched[]  = "caution: filename not matched:  %s\n";
const char ExclFilenameNotMatched[]  =
  "caution: excluded filename not matched:  %s\n";
#endif
*/
/*
 * UEN (Unzip Error New) is composed as folows:
 * a unsigned long (32 bits) Byte4 Byte3 Byte2 Byte1
 * Byte 1       Signed; (Old <= dll version 1.503) ZE_ error class (-5 to 18) (-2,17 not used)
 *                      Error return values.  The values 0..4 and 12..18 follow the conventions
 *                              of PKZIP.   The values 4..10 are all assigned to "insufficient memory"
 *                      by PKZIP, so the codes 5, 9 and 10 are used here for other purposes.
 *                              also 6, 7, 8 and 17 are not used yet.
 *                              Return codes of password fetches (negative = user abort; positive = error)
 *                              UENPW_ERROR was 5 but had to make it -5 since UENLOGIC uses 5
 *                              UENPW_CANCEL was -1 changed to -3 .. -1 inuse
 *                              UENPW_CANCELALL was -2 changed to -4
 * Byte 2       Sequence number in the UEN Error class: 1..255
 * Byte 3       Error string number in errors[] array or 0x7F if present in global pG->eremsg.
 * Byte 4       Not used yet.
 */

// #define UEN_OK                                  0       /* Success                                                                                                                              */

//#define UEN_EOF                         2       /* Unexpected end of zip file                                                                           */
//#define UEN_EOF01                               0x130102        /* in Process.c                                                                                                         */
//#define UEN_EOF02                               0x140202        /* in Extract.c                                                                                                         */
#if 0
// #define UEN_FORM                                3       /* Zip file structure error                                                                             */
// #define UEN_FORM01                      0x030103        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM02                      0x030203        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM03                      0x030303        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM04                      0x030403        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM05                      0x030503        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM06                      0x030603        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM07                      0x030703        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM08                      0x030803        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM09                      0x030903        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM10                      0x030A03        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM11                      0x030B03        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM12                      0x030C03        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM13                      0x030D03        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM14                      0x030E03        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM15                      0x030F03        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM16                      0x031003        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM17                      0x031103        /* in ZipFile.c readzipfile()                                                                           */
// #define UEN_FORM18                      0x081203        /* in Process.c                                                                                                         */
#endif
//#define UEN_MEM                         4       /* Out of memory                                                                                                                */
//#define UEN_MEM01                               0x040104        /* in process.c ProcessZipfiles()                                                               */
//#define UEN_MEM02                               0x040204        /* in deflate.c lm_init()                                                                                       */
//#define UEN_MEM03                               0x040304        /* in process.c ProcessZipfiles()                                                               */

//#define UEN_MISC                                6       /* RCV defined/changed errors                                                                           */
//#define UEN_MISC01                      0x060106        /* in Process.c                                                                                                         */
//#define UEN_MISC02                      0x070206        /* in Process.c                                                                                                         */
//#define UEN_MISC03                      0x7F0364        /* in Extract.c                                                                                                         */
//#define UEN_MISC04                      0x7F0464        /* in Extract.c                                                                                                         */
//#define UEN_MISC05                      0x7F0514        /* in Extract.c                                                                                                         */

// #define UEN_TEST                                8       /* zip test (-T) failed or out of memory                                                */
// #define UEN_TEST01                      0x7F0108        /* in Process.c                                                                                                         */
// #define UEN_TEST02                      0x7F0208        /* in Process.c                                                                                                         */

// #define UEN_ABORT                               9       /* user interrupt or termination                                                                        */
// #define UEN_ABORT01                     0x090109        /* in Tress.c flush_block()                                                                             */
// #define UEN_ABORT02                     0x090209        /* in Extract.c                                                                                                         */
// #define UEN_ABORT03                     0x090309        /* in Inflate.c, Extract.c                                                                                      */
// #define UEN_ABORT04                     0x090409        /* in Extract.c                                                                                                         */

// #define UEN_READ                                11      /* Error reading a file                                                                                         */
// #define UEN_READ01                      0x0B010B        /* in FileIO.c read failed, probably bad media                          */

// #define UEN_NAME                                13      /* Missing zip file                                                                                                     */
// #define UEN_NAME01                      0x0D010D        /* in FileIO.c                                                                                                                  */

// #define UEN_WRITE                               14      /* Error writing to a file                                                                                      */
// #define UEN_WRITE01                     0x0E010E        /* Write error in flush_outbuf                                                                  */

// #define UEN_PARMS                               16      /* Bad command line                                                                                                     */
// #define UEN_PARMS01                     0x100110        /* no zip filename received, was -1                                                             */
// #define UEN_PARMS02                     0x100210        /* struct size mismatch, was -2                                                                 */

#endif

