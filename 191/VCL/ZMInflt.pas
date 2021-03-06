unit ZMInflt;

//  ZMInflt.pas - restores data compressed with the 'deflate' algoritm.

(* ***************************************************************************
TZipMaster VCL originally by Chris Vleghert, Eric W. Engler.
  Present Maintainers and Authors Roger Aelbrecht and Russell Peters.
Copyright (C) 1997-2002 Chris Vleghert and Eric W. Engler
Copyright (C) 1992-2008 Eric W. Engler
Copyright (C) 2009, 2010, 2011, 2012, 2013 Russell Peters and Roger Aelbrecht

All rights reserved.
For the purposes of Copyright and this license "DelphiZip" is the current
 authors, maintainers and developers of its code:
  Russell Peters and Roger Aelbrecht.

Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
* Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
* Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
* DelphiZip reserves the names "DelphiZip", "ZipMaster", "ZipBuilder",
   "DelZip" and derivatives of those names for the use in or about this
   code and neither those names nor the names of its authors or
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL DELPHIZIP, IT'S AUTHORS OR CONTRIBUTERS BE
 LIABLE FOR ANYDIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT(INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.

contact: problems AT delphizip DOT org
updates: http://www.delphizip.org
 *************************************************************************** *)
//modified 2011-11-20

{$INCLUDE   '.\ZipVers.inc'}
{$IFDEF VER180}
{$WARN SYMBOL_PLATFORM OFF}
{$ENDIF}
{$Q-}  // range check off

{ .$define DEBUG }

interface

uses
  Windows, classes;

type
  phuft = ^huft;
  ppHuft = ^phuft;

  huft = packed record
    case Boolean of
      False:
        (e: Word; // number of extra bits or operation
          b: Word; // number of bits in this code or subcode
          n: Word); // literal, length base, or distance base
      True:
        (w: Cardinal; // Word; // actually AnsiChar[2]
          t: phuft); // pointer to next level of table
  end;

const
  UnzBufferSize = $8000;

type
  TTraceEvent = procedure(Sender: TObject; const msg: string) of object;
  TInProgressEvent = procedure(Sender: TObject; const cnt: Int64) of object;

type
  TZMInflate = class
  private
    outBuf: array of AnsiChar;
    inbuf: array of AnsiChar;
    inptr: Cardinal;
    ZipCount: Cardinal;
    fInStrm: TStream;
    fOutStrm: TStream;
    fCRC: Cardinal;
    incnt: Integer;
    HuftPool: array of huft;
    PoolIndex: Integer;
    fixed_tl: phuft;
    fixed_td: phuft;
    fixed_bl: Cardinal;
    fixed_bd: Cardinal;
    outPtr: Cardinal; // current position in slide
    BitBucket: Cardinal; // bit buffer
    BitsKept: Integer;   // bits in buffer
{$IFDEF DEBUG}
    fTrace: TTraceEvent;
{$ENDIF}
    fInSize: Int64;
    fOutSize: Int64;

    fInProgress: TInProgressEvent;
    FixedCnt: Integer;
    function NextByte: Cardinal;
    function Flush: Integer;
    procedure _GetMem(var p: phuft; Size: Integer);
    function GetHuftsUsed: Cardinal;

    function NeedBits(num: Integer): Boolean;
    function huft_build(var b: array of Word; n, s: Word;
      const d: array of Word; const e: array of Byte; tree: ppHuft;
      var m: Cardinal): Integer;
    function inflate_codes(tl, td: phuft; bl, bd: Integer): Integer;
    function inflate_stored: Integer;
    function inflate_fixed: Integer;
    function inflate_dynamic: Integer;
    function inflate_block(var e: Integer): Integer;
    function MakeFixedTables: Integer;
  public
// TODO: Create
//  constructor Create;
    procedure BeforeDestruction; override;
    procedure AfterConstruction; override;
    function CopyStored: Integer;
    function Inflate: Integer;
    property HuftsUsed: Cardinal read GetHuftsUsed;
    property InStream: TStream read fInStrm write fInStrm;
    property OutStream: TStream read fOutStrm write fOutStrm;
    property InSize: Int64 read fInSize write fInSize;
    property OutSize: Int64 read fOutSize write fOutSize;
    property CRC: Cardinal read fCRC write fCRC;
    property OnInProgress: TInProgressEvent read fInProgress write fInProgress;
{$IFDEF DEBUG}
    property Trace: TTraceEvent read fTrace write fTrace;
{$ENDIF}
  end;

function UndeflateQ(OutStream, InStream: TStream; Length: Int64; Method: Word;
  var CRC: Cardinal): Integer;
function ExtractZStream(OutStream, InStream: TStream; Length: Int64): Integer;

implementation

uses
  SysUtils, ZMStructs, ZMMsg, ZMUtils,
  ZMXcpt;//{$IFNDEF VERpre6}, ZMCompat{$ENDIF};

const
  __UNIT__ = 18 shl 23;

{$IFDEF VERpre6}
type
  PCardinal = ^Cardinal;
{$ENDIF}

{ TZMInflate }

// PKZIP_BUG_WORKAROUND applied permanently
(* PKZIP 1.93a problem--live with it *)

const
  BMAX         = 16;
  INVALID_CODE = 99;

  (* And'ing with mask_bits[n] masks the lower n bits *)
const
  mask_bits: array [0 .. 16] of Word = ($0000, $0001, $0003, $0007, $000F,
    $001F, $003F, $007F, $00FF, $01FF, $03FF, $07FF, $0FFF, $1FFF, $3FFF,
    $7FFF, $FFFF);

  // Tables for deflate from PKZIP's appnote.txt.
const
  (* Order of the bit length code lengths *)
  border: array [0 .. 18] of Cardinal = (16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11,
    4, 12, 3, 13, 2, 14, 1, 15);

const
  // Copy lengths for literal codes 257..285
  cplens: array [0 .. 30] of Word = (3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17,
    19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227,
    258, 0, 0);
  (* note: see note #13  about the 258 in this list. *)

  // * - Extra bits for literal codes 257..285 */
  cplext: array [0 .. 30] of Byte = (0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2,
    2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0, INVALID_CODE, INVALID_CODE);

const
  // Copy offsets for distance codes 0..29 (31 for Deflate64 or PKZIP_WORKAROUND)
  cpdist: array [0 .. 31] of Word = (1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49,
    65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
    8193, 12289, 16385, 24577, 32769, 49153);

const
  (* Extra bits for distance codes *)
  cpdext: array [0 .. 31] of Byte = (0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5,
    6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14);

const
  lbits: Integer = 9; // bits in base literal/length lookup table

const
  dbits: Integer = 6; // bits in base distance lookup table

  MAXLITLENS = 288;
  MAXDISTS   = 32;

const
  EOF: Cardinal = Cardinal(-1);
  INIT_POOL     = 1800;

procedure TZMInflate.BeforeDestruction;
begin
  inbuf := nil;
  outBuf := nil;
  inherited;
end;

procedure TZMInflate.AfterConstruction;
begin
  inherited;
  fInStrm := nil;
  fOutStrm := nil;
{$IFDEF DEBUG}
  fTrace := nil;
{$ENDIF}
  fixed_tl := nil;
  fixed_td := nil;
  fCRC := 0;
  SetLength(HuftPool, INIT_POOL);
end;

function TZMInflate.CopyStored: Integer;
const
  __ERR_DS_NoWrite = __UNIT__ + (265 shl 10) + DS_NoWrite;
var
  ToRead: Integer;
begin
  inptr := 0;
  outPtr := 0;
  ZipCount := 0;
  if @InStream = @OutStream then
    raise Exception.Create('Streams the same');
  SetLength(outBuf, UnzBufferSize + 1);
  inptr := 0;
  incnt := 0;
  fCRC := $FFFFFFFF;
  fOutSize := 0;
  if InSize > 0 then
  begin
    while fOutSize < InSize do
    begin
      if (fOutSize - InSize) > UnzBufferSize then
        ToRead := UnzBufferSize
      else
        ToRead := Integer(fOutSize - InSize);
      if InStream.Read(outBuf[0], ToRead) <> ToRead then
      begin
        Result := -__ERR_DS_NoWrite;
        exit;
      end;
      outPtr := ToRead;
      if outPtr = UnzBufferSize then
      begin
        if assigned(OnInProgress) then
          OnInProgress(self, UnzBufferSize);
        Flush;
      end;
    end;
  end;
  Flush;
  Result := 0;
  fCRC := fCRC xor $FFFFFFFF;
  outBuf := nil;
end;

procedure TZMInflate._GetMem(var p: phuft; Size: Integer);
const
  __ERR_GE_NoMem = __UNIT__ + (291 shl 10) + GE_NoMem;
var
  nxt: Integer;
begin
  nxt := PoolIndex + Size;
  if nxt > high(HuftPool) then
    raise EZipMaster.CreateMsgDisp(__ERR_GE_NoMem, True);
//    SetLength(HuftPool, (nxt or 15) + 1);
  p := @HuftPool[PoolIndex];
  PoolIndex := nxt;
end;

(* If BMAX needs to be larger than 16, then h and x[] should be ulg. *)
(* maximum bit length of any code (16 for explode) *)
(* maximum number of codes in any set *)
(* ===========================================================================
  * Given a list of code lengths and a maximum table size, make a set of
  * tables to decode that set of codes.  Return zero on success, one if
  * the given code set is incomplete (the tables are still built in this
  * case), two if the input is invalid (all zero length codes or an
  * oversubscribed set of lengths), and three if not enough memory.
  * The code with value 256 is special, and the tables are constructed
  * so that no bits beyond that code are fetched when that code is
  * decoded.
  *b :: Code lengths in bits (all assumed <= BMAX).
  n :: Number of codes (assumed <= N_MAX).
  s :: Number of simple-valued codes (0..s-1).
  *d :: List of base values for non-simple codes.
  *e :: List of extra bits for non-simple codes.
  **tree :: Result: starting table.
  *m :: Maximum lookup bits, returns actual.
*)
function TZMInflate.huft_build(var b: array of Word; n, s: Word;
  const d: array of Word; const e: array of Byte; tree: ppHuft;
  var m: Cardinal): Integer;
type
  HArray = array [0 .. 4095] of huft;
  pHArray = ^HArray;
var
  a: Cardinal;
  c: array [0 .. BMAX] of Word;
  el: Cardinal;
  f: Cardinal;
  g: Cardinal;
  h: Integer;
  ha: pHArray;
  i: Cardinal;
  ii: Cardinal;
  j: Cardinal;
  k: Cardinal;
  lt: PCardinal;
  lx: array [-1 .. BMAX + 1] of Cardinal;
  q: phuft;
  r: huft;
  ti: Cardinal;
  tt: phuft;
  u: array [0 .. -1 + BMAX] of phuft;
  v: array [0 .. -1 + 288] of Word;
  vi: Cardinal;
  w: Word;
  x: array [0 .. BMAX] of Word;
  y: Integer;
  z: Word;
begin
  // Generate counts for each bit length
  // set length of EOB code, if any
  if n > 256 then
    el := b[256]
  else
    el := BMAX;

  tree^ := nil; // in case of failure
  FillChar(c[0], sizeof(c), 0);

  for i := 0 to pred(n) do // assume all entries <= BMAX
  begin
    Inc(c[b[i]]);
  end;

  if (c[0] = n) then
  begin // null input--all zero length codes
    m := 0;
    Result := 0;
    exit;
  end;

  // Find minimum and maximum length, bound *m by those
  j := 1;
  while j <= BMAX do
  begin
    if (c[j] <> 0) then
      break;
    Inc(j);
  end;
  k := j; // minimum code length
  if (m < j) then
    m := j;
  i := BMAX;
  while i > 0 do
  begin
    if (c[i] <> 0) then
      break;
    dec(i);
  end;
  g := i; // maximum code length

  if (m > i) then
    m := i;

  // Adjust last length count to fill out codes, if needed
  Result := 2;
  y := 1 shl j;
  while j < i do
  begin
    dec(y, c[j]);
    if y < 0 then
      exit; // bad input: more codes than bits
    Inc(j);
    y := y shl 1;
  end;
  dec(y, c[i]);
  if y < 0 then
    exit;
  Inc(c[i], y);

  // Generate starting offsets into the value table for each length
  j := 0;
  x[1] := 0;
  for i := 1 to pred(g) do
  begin
    Inc(j, c[i]);
    x[1 + i] := j;
  end;

  // Make a table of values in order of bit lengths
  FillChar(v[0], sizeof(v), 0);
  for i := 0 to pred(n) do
  begin
    j := b[i];
    if j <> 0 then
    begin
      v[x[j]] := i;
      Inc(x[j]);
    end;
  end;
  n := x[g]; // length of v

  // Generate the Huffman codes and for each, make the table entries
  i := 0;
  x[0] := 0; // first Huffman code is zero
  vi := 0; // grab values in bit order
  h := -1; // no tables yet--level -1
  lx[-1] := 0;
  w := 0; // no bits decoded yet
  u[0] := nil; // just to keep compilers happy
  q := nil; // ditto
  z := 0; // ditto

  // go through the bit lengths (k already is bits in shortest code)
  while k <= g do
  begin
    a := c[k];
    while a > 0 do
    begin
      dec(a);
      // here i is the Huffman code of length k bits for value v[vi]
      // make tables up to required level
      while k > w + lx[h] do
      begin
        w := w + lx[h]; // add bits already decoded
        Inc(h);

        // compute minimum size table less than or equal to m bits
        z := g - w;
        if z > m then
          z := m; // upper limit
        j := k - w;
        f := 1 shl j;
        if f > succ(a) then
        begin (* try a k-w bit table *)
          // too few codes for k-w bit table
          dec(f, a + 1);
          // deduct codes from patterns left
          // xp := @c[k];
          ii := k;
          Inc(j);
          while j < z do
          begin // try smaller tables up to z bits
            f := f shl 1;
            Inc(ii);
            if f <= c[ii] then
              break;
            // enough codes to use up j bits
            dec(f, c[ii]); // else deduct codes from patterns
            Inc(j);
          end;
        end;

        if (w + j > el) and (w < el) then
          j := el - w; // make EOB code end at table
        z := 1 shl j; // table entries for j-bit table
        lx[h] := j; // set table size in stack

        // allocate and link in new table
        _GetMem(q, succ(z));
        if q = nil then
        begin
          Result := 3; // not enough memory
          exit;
        end;
        tt := q;
        Inc(q);
        tree^ := q; // link to prev
        tree := @tt.t;
        tree^ := nil; // end of chain

        u[h] := q; // table starts after link

        // connect to last table, if there is one
        if (h > 0) then
        begin
          x[h] := i; // save pattern for backing up
          r.b := Word(lx[h - 1]); // bits to dump before this table
          r.e := Word(32 + j); // bits in this table
          r.t := q; // pointer to this table
          j := (i and ((1 shl w) - 1)) shr (w - lx[h - 1]);
          ha := pHArray(u[h - 1]);
          ha[j].w := r.w;
          ha[j].t := r.t;
        end;
      end;

      // set up table entry in r
      r.b := Word(k - w);
      if vi >= n then
        r.e := Word(INVALID_CODE) // out of values--invalid code
      else
      begin
        ii := v[vi];
        if ii < s then
        begin
          if ii < 256 then // 256 is end-of-block code
            r.e := 32
          else
            r.e := 31;
          r.n := ii; // simple code is just the value
        end
        else
        begin
          r.e := Word(e[ii - s]); // non-simple--look up in lists
          r.n := d[ii - s];
          // inc(vi);
        end;
        Inc(vi);
      end;
      // fill code-like entries with r
      f := 1 shl (k - w);
      j := (i shr w);
      while j < z do
      begin
        ha := pHArray(q);
        ha[j].w := r.w;
        ha[j].t := r.t;
        Inc(j, f);
      end;

      // backwards increment the k-bit code i
      j := 1 shl pred(k);
      while (i and j) <> 0 do
      begin
        i := i xor j;
        j := j shr 1;
      end;
      i := i xor j;

      // backup over finished tables
      while ((i and ((1 shl w) - 1)) <> x[h]) do
      begin
        dec(h);
        dec(w, lx[h]);
      end; // don'tree need to update q
    end;
    Inc(k);
  end;

  // return actual size of base table
  m := lx[0];

  // Return true (1) if we were given an incomplete table
  if (y <> 0) and (g <> 1) then
    Result := 1
  else
    Result := 0;
end;

(* ===========================================================================
  * decompress an inflated block
  *e :: Last block flag.
*)
function TZMInflate.inflate_block(var e: Integer): Integer;
var
  t: Cardinal;
begin
  Result := 1; // error

  // read in last block bit
  if NeedBits(1) then
    exit; // past end

  e := BitBucket and 1;
  BitBucket := BitBucket shr (1);
  dec(BitsKept, 1);

  // read in block type
  if NeedBits(2) then
    exit;

  PoolIndex := FixedCnt;  // 'free' used hufts except fixed

  t := BitBucket and 3;
  BitBucket := BitBucket shr (2);
  dec(BitsKept, 2);

  // inflate that block type
  case t of
    2:
      Result := inflate_dynamic;
    1:
      Result := inflate_fixed;
    0:
      Result := inflate_stored;
  else
    Result := 2; // bad block
  end;
end;

(* ===========================================================================
  * inflate (decompress) the codes in a deflated (compressed) block.
  * Return an error code or zero if it all goes ok.
  *tl, *td :: Literal/length and distance decoder tables.
  bl, bd  :: Number of bits decoded by tl[] and td[].
*)
function TZMInflate.inflate_codes(tl, td: phuft; bl, bd: Integer): Integer;
var
  d: Cardinal;
  e: Cardinal;
  md: Cardinal;
  ml: Cardinal;
  n: Cardinal;
  t: phuft;
begin
  // if assigned(Trace) then
  // Trace(self, 'inflate codes');
  Result := 1;

  (* inflate the coded data *)
  ml := mask_bits[bl]; // precompute masks for speed
  md := mask_bits[bd];

  while (True) do // do until end of block
  begin
    if NeedBits(bl) then
      exit;

    t := tl;
    Inc(t, BitBucket and ml);
    while True do
    begin
      BitBucket := BitBucket shr Cardinal(t^.b);
      dec(BitsKept, Cardinal(t^.b));
      e := Cardinal(t^.e);
      // if outPtr > 24100 then
      // Trace(self, Format('%d %d %p',[outPtr, e, t^.t]) );
      if e = 32 then // it's a literal
      begin
        outBuf[outPtr] := AnsiChar(t^.n);
        Inc(outPtr);
        if outPtr = UnzBufferSize { slide_size } then
          Flush;
        break;
      end;
      if e < 31 then // it's a length
      begin
        // get block length
        if NeedBits(e) then
          exit;
        n := t^.n + (BitBucket and mask_bits[e]);
        BitBucket := BitBucket shr e;
        dec(BitsKept, e);
        // decode distance of block to copy
        if NeedBits(bd) then
          exit;
        t := td;
        Inc(t, (BitBucket and md));
        while True do
        begin
          BitBucket := BitBucket shr Cardinal(t^.b);
          dec(BitsKept, Cardinal(t^.b));
          e := Cardinal(t^.e);
          if e < 32 then
            break;
          if e = INVALID_CODE then
            exit; // 1
          e := e and 31;
          if NeedBits(e) then
            exit;
          t := t^.t;
          Inc(t, (BitBucket and mask_bits[e]));
        end;
        if NeedBits(e) then
          exit;
        d := outPtr - t^.n - (BitBucket and mask_bits[e]);
        BitBucket := BitBucket shr e;
        dec(BitsKept, e);
        // do the copy
        repeat
          d := d and (UnzBufferSize - 1);
          if d > outPtr then
            e := UnzBufferSize - d
          else
            e := UnzBufferSize - outPtr;
          if e > n then
            e := n;
          dec(n, e);

          if (outPtr - d >= e) then
          begin // * (this test assumes unsigned comparison) */
            move(outBuf[d], outBuf[outPtr], e);
            Inc(outPtr, e);
            Inc(d, e);
          end
          else // * do it slowly to avoid memcpy() overlap */
            repeat
              outBuf[outPtr] := outBuf[d];
              Inc(outPtr);
              Inc(d);
              dec(e);
            until e < 1;
          if outPtr = UnzBufferSize then
          begin
            Flush;
          end;
        until n = 0;
        break;
      end; // e < 31
      if e = 31 then // it's the EOB signal
      begin
        Result := 0;
        exit;
      end;
      if e = INVALID_CODE then
        exit;
      e := e and 31;
      if NeedBits(e) then
        exit;
      t := t^.t;
      Inc(t, BitBucket and mask_bits[e]);
    end;
  end;
  Result := 0;
end;

(* ===========================================================================
  * decompress an inflated type 2 (dynamic Huffman codes) block.
*)
function TZMInflate.inflate_dynamic: Integer;
var
  i: Cardinal; // temporary variables
  j: Cardinal;
  l: Cardinal; // last length
  m: Cardinal; // mask for bit lengths table
  n: Cardinal; // number of lengths to get
  tl: phuft; // literal/length code table
  td: phuft; // distance code table
  bl: Cardinal; // lookup bits for tl
  bd: Cardinal; // lookup bits for td
  nb: Cardinal; // number of bit length codes
  nl: Cardinal; // number of literal/length codes
  nd: Cardinal; // number of distance codes
  ll: array [0 .. -1 + 288 + 32] of Word;
  // literal/length and distance code lengths
begin
  // if assigned(Trace) then
  // Trace(self, 'in inflate_dynamic');
  Result := 1;

  // read in table lengths
  if NeedBits(5) then
    exit;

  nl := 257 + (BitBucket and $1F); // number of literal/length codes
  BitBucket := BitBucket shr (5);
  dec(BitsKept, 5);

  if NeedBits(5) then
    exit;

  nd := 1 + (BitBucket and $1F); // number of distance codes
  BitBucket := BitBucket shr (5);
  dec(BitsKept, 5);

  if NeedBits(4) then
    exit;

  nb := 4 + (BitBucket and $F); // number of bit length codes
  BitBucket := BitBucket shr (4);
  dec(BitsKept, 4);

  if (nl > 288) or (nd > 32) then
    exit; // bad lengths

  // read in bit-length-code lengths
  for j := 0 to pred(nb) do
  begin
    if NeedBits(3) then
      exit;

    ll[border[j]] := BitBucket and 7;
    BitBucket := BitBucket shr (3);
    dec(BitsKept, 3);
  end;

  for j := nb to 18 do
    ll[border[j]] := 0;

  // build decoding table for trees--single level, 7 bit lookup
  bl := 7;
  i := huft_build(ll, 19, 19, [], [], @tl, bl);
  if bl = 0 then
    i := 1;
  if i <> 0 then
  begin
    Result := i; // incomplete code set
    exit;
  end;

  // read in literal and distance code lengths
  n := nl + nd;
  m := mask_bits[bl];
  l := 0;
  i := 0;
  while i < n do
  begin
    if NeedBits(bl) then
      exit;

    td := tl;
    Inc(td, BitBucket and m);
    j := Cardinal(td^.b);
    BitBucket := BitBucket shr (j);
    dec(BitsKept, j);

    j := td^.n;
    if (j < 16) then // length of code in bits (0..15)
    begin
      l := j;
      ll[i] := l; // save last length in l
      Inc(i);
    end
    else
      if (j = 16) then
      begin // repeat last length 3 to 6 times
        if NeedBits(2) then
          exit;

        j := 3 + (BitBucket and 3);
        BitBucket := BitBucket shr (2);
        dec(BitsKept, 2);

        if (i + j > n) then
          exit;
        while (j <> 0) do
        begin
          dec(j);
          ll[i] := l;
          Inc(i);
        end;
      end
      else
        if (j = 17) then
        begin // 3 to 10 zero length codes
          if NeedBits(3) then
            exit;

          j := 3 + (BitBucket and 7);
          BitBucket := BitBucket shr (3);
          dec(BitsKept, 3);

          if (i + j > n) then
            exit;
          while (j <> 0) do
          begin
            dec(j);
            ll[i] := 0;
            Inc(i);
          end;
          l := 0;
        end
        else
        begin // j == 18: 11 to 138 zero length codes
          if NeedBits(7) then
            exit;

          j := 11 + (BitBucket and $7F);
          BitBucket := BitBucket shr (7);
          dec(BitsKept, 7);

          if (i + j > n) then
            exit;
          while (j <> 0) do
          begin
            dec(j);
            ll[i] := 0;
            Inc(i);
          end;
          l := 0;
        end;
  end;

  // build the decoding tables for literal/length and distance codes
  bl := lbits;
  i := huft_build(ll, nl, 257, cplens, cplext, @tl, bl);
  if bl = 0 then
    i := 1;
  if i <> 0 then
  begin
{$IFDEF DEBUG}
    if i = 1 then
    begin
      if assigned(Trace) then
        Trace(self, 'Fatal error: incomplete l-tree');
    end;
{$ENDIF}

    Result := i; // incomplete code set
    exit;
  end;

  bd := dbits;
  i := huft_build(ll[nl], nd, 0, cpdist, cpdext, @td, bd);
  if bd = 0 then
    i := 1;
  if i <> 0 then
  begin
{$IFDEF DEBUG}
    if i = 1 then
    begin
      if assigned(Trace) then
        Trace(self, 'Fatal error: incomplete d-tree');
    end;
{$ENDIF}

    Result := i;
    exit; // incomplete code set
  end;

  // decompress until an end-of-block code
  if (inflate_codes(tl, td, bl, bd) <> 0) then
  begin
{$IFDEF DEBUG}
    if assigned(Trace) then
      Trace(self, 'err returned from inflate_codes');
{$ENDIF}
    exit;
  end;

  // if assigned(Trace) then
  // Trace(self, 'inflate_dynamic returning 0');
  Result := 0;
end;

(* ===========================================================================
  * decompress an inflated type 1 (fixed Huffman codes) block.  We should
  * replace this with a custom decoder.
*)
function TZMInflate.inflate_fixed: Integer;
begin
  // Decompress until an end-of-block code.
  Result := inflate_codes(fixed_tl, fixed_td, fixed_bl, fixed_bd);
end;

{ ===========================================================================
  * "decompress" an inflated type 0 (stored) block.
}
function TZMInflate.inflate_stored: Integer;
var
  n: Cardinal;
begin
  Result := 1; // error
  // if assigned(Trace) then
  // Trace(self, 'extracting stored block');

  // go to byte boundary
  n := BitsKept and 7;
  BitBucket := BitBucket shr (n);
  dec(BitsKept, n);

  // get the length and its complement
  if NeedBits(16) then
    exit;
  n := (BitBucket and $FFFF); // count
  BitBucket := BitBucket shr 16;
  dec(BitsKept, 16);

  if NeedBits(16) then
    exit;

  // b = count complement
  if (n <> ((not BitBucket) and $FFFF)) then
    exit; // error in compressed data
  BitBucket := BitBucket shr (16);
  dec(BitsKept, 16);

  // read and output the compressed data
  while (n > 0) do
  begin
    dec(n);
    if NeedBits(8) then
      exit;
    outBuf[outPtr] := AnsiChar(BitBucket);
    Inc(outPtr);
    if outPtr >= UnzBufferSize then
    begin
      if assigned(OnInProgress) then
        OnInProgress(self, outPtr);
      Flush;
    end;

    BitBucket := BitBucket shr (8);
    dec(BitsKept, 8);
  end;

  Result := 0;
end;

function TZMInflate.NeedBits(num: Integer): Boolean;
var
  c: Cardinal;
begin
  Result := False; // ok
  while BitsKept < num do
  begin
    c := NextByte;
    if c >= 256 then
    begin
      Result := BitsKept < 0; // true if neg
      exit;
    end;
    BitBucket := BitBucket or (c shl BitsKept);
    Inc(BitsKept, 8);
  end;
end;

function TZMInflate.NextByte: Cardinal;
var
  bytes: Integer;
begin
  if inptr >= ZipCount then
  begin
    // fill buffer
    bytes := high(inbuf);
    if fInSize < bytes then
      bytes := fInSize;
    bytes := InStream.Read(inbuf[0], bytes);
    if bytes <= 0 then
      ZipCount := 0 // error
    else
    begin
      ZipCount := Cardinal(bytes);
      dec(fInSize, bytes);
    end;
    inptr := 0;
  end;

  if ZipCount < 1 then
  begin
    inptr := 0;
    Result := $80000000;
  end
  else
  begin
    Result := Cardinal(inbuf[inptr]);
    Inc(inptr);
  end;
end;

function TZMInflate.Inflate: Integer;
var
  e: Integer;
begin
  inptr := 0;
  ZipCount := 0;
  if @InStream = @OutStream then
    raise Exception.Create('Streams the same');
  SetLength(inbuf, UnzBufferSize);
  SetLength(outBuf, UnzBufferSize + 1);
  inptr := 0;
  incnt := 0;

  outPtr := 0;
  BitsKept := 0;
  BitBucket := 0;

  MakeFixedTables;
  fCRC := Cardinal(-1);
  fOutSize := 0;
  repeat
    Result := inflate_block(e);
    if Result <> 0 then
      exit;
  until e <> 0;

  Flush;
  Result := 0;
  fCRC := fCRC xor $FFFFFFFF;
  // {$IFDEF DEBUG}
  // if assigned(Trace) then
  // Trace(self, Format('Inflate returned %d',[Result]));
  // {$ENDIF}
  outBuf := nil;
end;

function TZMInflate.Flush: Integer;
var
  p: Cardinal;
begin
  Result := 0;
  if outPtr < 1 then
    exit;
  CRC := Update_CRC32(CRC, @outBuf[0], outPtr);
  Inc(fOutSize, outPtr);
  p := outPtr;
  outPtr := 0;
  if assigned(OutStream) then
    try
      OutStream.WriteBuffer(outBuf[0], p);
    except
      Result := -DS_NoWrite;
    end;
end;

function TZMInflate.GetHuftsUsed: Cardinal;
begin
  Result := PoolIndex;
end;

function TZMInflate.MakeFixedTables: Integer;
var
  i: Integer;
  l: array [0 .. -1 + 288] of Word;
begin
  // if first time, set up tables for fixed blocks
  Result := 0;
  if (fixed_tl = nil) then
  begin
    PoolIndex := 0;
{$IFDEF DEBUG}
    if assigned(Trace) then
      Trace(self, 'literal block');
{$ENDIF}
    // literal table
    for i := 0 to pred(144) do
      l[i] := 8;
    for i := 144 to pred(256) do
      l[i] := 9;
    for i := 256 to pred(280) do
      l[i] := 7;
    for i := 280 to pred(288) do
      l[i] := 8;
    // make a complete, but wrong code set
    fixed_bl := 7;
    Result := huft_build(l, 288, 257, cplens, cplext, @fixed_tl, fixed_bl);
    if Result <> 0 then
    begin
      fixed_tl := nil;
      exit;
    end;

    // distance table
    for i := 0 to pred(32) do
      l[i] := 5; // make an incomplete code set
    fixed_bd := 5;
    Result := huft_build(l, 30, 0, cpdist, cpdext, @fixed_td, fixed_bd);
    if Result > 1 then
    begin
      fixed_tl := nil;
      exit;
    end;
    FixedCnt := PoolIndex + 1;
{$IFDEF DEBUG}
    if assigned(Trace) then
      Trace(self, 'Made fixed tables = ' + IntToStr(PoolIndex) +
        '  Sizeof(Huft) = ' + IntToStr(sizeof(huft)));
{$ENDIF}
  end;
end;

function UndeflateQ(OutStream, InStream: TStream; Length: Int64; Method: Word;
  var CRC: Cardinal): Integer;
const
  __ERR_DS_Unsupported = __UNIT__ + (1190 shl 10) + DS_Unsupported;
  __ERR_DS_BadCRC = __UNIT__ + (1204 shl 10) + DS_BadCRC;
var
  Inflater: TZMInflate;
begin
  Result := -__ERR_DS_Unsupported;
  if (Method = METHOD_DEFLATED) or (Method = METHOD_STORED) then
  begin
    Inflater := TZMInflate.Create;
    try
      Inflater.InStream := InStream;
      Inflater.OutStream := OutStream;
      Inflater.InSize := Length;
      if Method = METHOD_STORED then
        Result := Inflater.CopyStored
      else
        Result := Inflater.Inflate;
      if (Result = 0) and (Inflater.CRC <> CRC) then
      begin
        Result := -__ERR_DS_BadCRC;
        CRC := Inflater.CRC;
      end;
    finally
      Inflater.Free;
    end;
  end;
end;

function ExtractZStream(OutStream, InStream: TStream; Length: Int64): Integer;
const
  __ERR_DS_ReadError = __UNIT__ + (1222 shl 10) + DS_ReadError;
var
  Heder: TZM_StreamHeader;
begin
  if InStream.Read(Heder, sizeof(TZM_StreamHeader)) <> sizeof(TZM_StreamHeader)
  then
  begin
    Result := -__ERR_DS_ReadError;
    exit;
  end;
  Result := UndeflateQ(OutStream, InStream, Length - sizeof(TZM_StreamHeader),
    Heder.Method, Heder.CRC);
end;

end.
