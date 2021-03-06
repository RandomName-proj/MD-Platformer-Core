; ==============================================================
; --------------------------------------------------------------
; MD Platformer Core
;
;   by Mega Drive Developers Collective
;      AURORA FIELDS 2020/12
;
;   VRAM allocation processing and dynamic art loading library
; --------------------------------------------------------------

; ==============================================================
; --------------------------------------------------------------
; macro to include dynamic map data
;
;   tile =	tile ID to use, from $000 to $FFF
;   length =	number of tiles to transfer, from 1 to 16
;
; Note: Attempting to transfer 16 tiles from $FFF is invalid
; --------------------------------------------------------------

dynpc		macro tile, length
	if ((\length) < 1) | ((\length) > 16)
		inform 2, "Dynamic mappings length \length is invalid. Must be 1 to 16"
	endif

	if ((\tile) < 0) | ((\tile) > $FFF)
		inform 2, "Dynamic mappings tile ID \tile is invalid. Must be 0 to $FFF"
	endif
		dc.w ((((\tile) << 4) | ((\length) - 1)) + 1) & $FFFF
	endm

dynpe		macro
		dc.w 0						; end token
	endm
; ==============================================================
; --------------------------------------------------------------
; Routine to process dynamic art objects
;
; in:
;   a0 = target object
;
; thrash: d0-d6/a0-a1/a3-a4
; --------------------------------------------------------------

ProcAlloc:
		lea	DartList.w,a1				; load dynamic art list to a1
		add.b	#dynallocdelta,DynAllocTimer.w		; update dynamic allocator timer
		bcs.w	AllocRefactor				; if overflowed, force a refactor
		dbset	dyncount,d0				; load number of dynamic objects to d0
; --------------------------------------------------------------

.dloop
		tst.w	(a1)					; check if this is active
		bpl.s	.skip					; if not, branch

		moveq	#0,d4
		move.w	(a1),a0					; load the parent to a0
		move.b	frame(a0),d4				; load display frame to d4
		cmp.b	dlast(a1),d4				; check if we are currently displaying this frame
		beq.s	.skip					; if so, just skip it

		cmp.b	#$FF,dbit(a1)				; check if this is an invalid object
		beq.s	.skip					; if yes, do not update!!
		bsr.s	AllocUpdate				; update this
; --------------------------------------------------------------

.skip
		lea	dsize(a1),a1				; go to next object
		dbf	d0,.dloop				; loop for all objects

ProcAlloc_Rts:
		rts
; ==============================================================
; --------------------------------------------------------------
; Routine to update dynamic art object in VRAM
;
; in:
;   d4 = frame ID
;   a0 = object
;   a1 = dynamic art address
;
; thrash: d3-d6/a3-a4
; --------------------------------------------------------------

AllocUpdate:
		move.b	d4,dlast(a1)				; save d4 as the new last frame
		beq.s	ProcAlloc_Rts				; if frame 0, nothing will display anyway
		move.l	dart(a1),d6				; load art data to d6
		move.l	dmap(a1),a3				; load art mappings to a3

		move.w	tile(a0),d5				; load tile settings to d5
		and.w	#$7FF,d5				; get only the settings part
		lsl.w	#5,d5					; get the VRAM offset to d5
; ==============================================================
; --------------------------------------------------------------
; Routine to add mappings frame to DMA queue
;
; in:
;   d4 = frame ID (must be word!!)
;   d5 = destination VRAM address
;   d6 = art data address
;   a3 = mappings data address
;
; thrash: d3-d6/a3-a4
; --------------------------------------------------------------

dmaQueueMaps:
		add.w	d4,d4					; double offset
		add.w	-2(a3,d4.w),a3				; add table offset to get mappings data to a3
; --------------------------------------------------------------

dmaQueueMapData:
		bra.s	.checktoken
; --------------------------------------------------------------

.proctoken
		moveq	#$F,d3					; load the num of tiles to d3
		and.w	d4,d3					; and with the read word
		addq.w	#1,d3					; +1 for 1 to 16 tiles
		lsl.w	#4,d3					; multiply by 16 (half of a tile size)

		and.l	#$FFF0,d4				; get only the tile offset portion to d4
		add.l	d4,d4					; double offset, totaling the size of a tile
		add.l	d6,d4					; add art address to d4

		bsr.s	dmaQueueAdd				; add this to DMA queue
		add.w	d3,d5					; add tile length to VRAM destination address
		add.w	d3,d5					; twice because it was / 2
; --------------------------------------------------------------

.checktoken
		moveq	#-1,d4					; set up data so that range from 0 to $FFFE is possible only
		add.w	(a3)+,d4				; add next data to d4
		bcs.s	.proctoken				; if not end marker, process token
		rts						; end of list
; ==============================================================
; --------------------------------------------------------------
; Routine to queue DMA entries
;
; in:
;   d3 = transfer length
;   d4 = source ROM address
;   d5 = destination VRAM address
;
; thrash: d2/d4/a4
; --------------------------------------------------------------

dmaQueueAdd:
		move.w	DMAQueueAddr.w,a4			; load DMA queue free entry pointer to a4
	if DEBUG
		cmp.w	#0,a4					; check if the queue is full
		bpl.s	.full					; branch if so
	endif
; --------------------------------------------------------------

		lsr.l	#1,d4					; halve source address

	if SAFE_DMA
		move.w	d3,d2					; copy length to d2
		neg.w	d2					; negate lenght
		sub.w	d4,d2					; sub low word of source address from negative length
		bcc.s	.transfer				; do only a single transfer if no boundary was crossed
; --------------------------------------------------------------

		move.l	d4,-(sp)				; store source address in stack because it will get borked
		bsr.s	.transfer				; transfer the first portion
		move.l	(sp)+,d4				; get source address back

		moveq	#0,d2					; clear d2
		sub.w	d4,d2					; subtract source address from d2
		sub.w	d2,d3					; subtract this value from the length
		add.l	d2,d4					; add to the source address

		add.w	d2,d5					; and finally add to the VRAM address
		add.w	d2,d5					; twice because it was halved

.transfer
	endif
; --------------------------------------------------------------

		movep.l	d4,3(a4)				; fill in the source address (writes an extra byte, gets overwritten)
		and.b	#$7F,5(a4)				; clear any unfortunate bits

		movep.w	d3,1(a4)				; fill transfer length
		move.b	#$94,(a4)				; set the initial register (because this was an end token before)
		lea	2*5(a4),a4				; skip to VDP command portion
; --------------------------------------------------------------

		moveq	#0,d4					; clear entirity of d4
		move.w	d5,d4					; copy VRAM address to d4
		lsl.l	#2,d4					; shift the 2 upper bits to upper word
		lsr.w	#2,d4					; shift rest of the bits in place

		swap	d4					; swap words
	vdp	or.l,0,VRAM,WDMA,d4				; enable VRAM DMA mode
		move.l	d4,(a4)+				; put the command into DMA queue
; --------------------------------------------------------------

		move.w	a4,DMAQueueAddr.w			; save the new DMA queue free entry pointer
		clr.w	(a4)					; set an end token (can overwrite DMAQueueAddr!)
; --------------------------------------------------------------

	if DEBUG
		rts

.full
		exception	exFullDMA			; DMA queue is full
	else
.full
		rts
	endif
; ==============================================================
; --------------------------------------------------------------
; Routine to refactor dynamic art objects in VRAM
;
; in:
;   a0 = target object
;
; thrash: d0-d6/a0-a1/a3-a4
; --------------------------------------------------------------

AllocRefactor:
		lea	DynAllocTable.w,a0			; load alloc table to a0

		moveq	#0,d0					; prepare bit to d0
		moveq	#0,d2					; prepare first free bit to d2
		dbset	dynallocbits,d1				; prepare max num of bits to d1
; --------------------------------------------------------------

.ckclr
		btst	d0,(a0)					; check if bit is set
		beq.s	.ckset					; if not, find if there are any set bits
		addq.b	#1,d0					; go to next bit
		addq.b	#1,d2					;

		bclr	#3,d0					; check if the byte is now all done
		sne	d3					; if yes, set d3
		ext.w	d3					; extend to word
		sub.w	d3,a0					; sub from the alloc pointer
		dbf	d1,.ckclr				; loop until we find a bit that is clear
		rts						; no free tiles anywhere, refactoring is not necessary
; --------------------------------------------------------------

.ckset	; TODO: broken
	;	btst	d0,(a0)					; check if bit is set
	;	bne.s	.refac					; if yes, we must refactor
	;	addq.b	#1,d0					; go to next bit

	;	bclr	#3,d0					; check if the byte is now all done
	;	sne	d3					; if yes, set d3
	;	ext.w	d3					; extend to word
	;	sub.w	d3,a0					; sub from the alloc pointer
	;	dbf	d1,.ckset				; loop until we find a bit that is clear
	;	rts						; no refactoring needed
; --------------------------------------------------------------

	; this actually refactors all the art
.refac
		lea	DartList.w,a1				; load dynamic art list to a1
		dbset	dyncount,d0				; load number of dynamic objects to d0
		move.w	d2,d1					; copy free bit to d1

.reloop
		tst.w	(a1)					; check if this is active
		bpl.w	.skip					; if not, branch
		cmp.b	dbit(a1),d1				; check if this was after the first free bit
		bhi.s	.ckupdate				; if not, check if we need to update anyway
; --------------------------------------------------------------

		moveq	#0,d3					; clear d3
		move.b	dwidth(a1),d3				; load object width to d3
		neg.w	d3					; negate it (this way we can check if the object fits)
		add.w	#dynallocbits,d3			; add the max number of bits to d3

		move.w	(a1),a0					; load the parent to a0
		cmp.b	d2,d3					; check if this bit is too much
		bhi.s	.yesbit					; if yes, do not process this object

		st	dbit(a1)				; forcibly hide object
		bset	#norender,flags(a0)			; forcibly disable sprites
		bra.s	.skip
; --------------------------------------------------------------

.yesbit
		bclr	#norender,flags(a0)			; forcibly enable sprites
		move.b	d2,dbit(a1)				; set the bit address

		move.w	tile(a0),d4				; load tile settings to d4
		and.w	#$F800,d4				; get only the settings part

		move.w	d2,d3					; copy the bit offset we are in
		fmulu.w	dynallocsize,d3,d5			; multiply by number of tiles
		add.w	#vDynamic/32,d3				; add the initial tile offset to d3
		or.w	d3,d4					; then save the tile address
		move.w	d4,tile(a0)				; save as tile settings

		moveq	#0,d4
		move.b	frame(a0),d4				; load display frame to d4

	if SAFE_DMA
		move.w	d2,-(sp)				; push d2 to stack because its modified
		bsr.w	AllocUpdate				; update art
		move.w	(sp)+,d2				; pop d2 from stack bto restore it
	else
		bsr.w	AllocUpdate				; update art
	endif
; --------------------------------------------------------------

		moveq	#0,d4
		move.b	dwidth(a1),d4				; load number of bits to reserve

		move.w	d2,d3					; copy bit to d3
		lsr.w	#3,d3					; divide by 8 (8 bits per byte)
		add.w	#DynAllocTable,d3			; add alloc table to d3
		move.w	d3,a2					; load the final address to a2

		moveq	#7,d3					; get only the bit to d3
		and.w	d2,d3					; and bit with d3
		add.w	d4,d2					; go to the bit after this object

		subq.w	#1,d4					; account for dbf
; --------------------------------------------------------------

.setbit
		bset	d3,(a2)					; set the bit
		addq.b	#1,d3					; go to next bit

		bclr	#3,d3					; check if the byte is now all done
		sne	d5					; if yes, set d2
		ext.w	d5					; extend to word
		sub.w	d5,a2					; sub from the alloc pointer
		dbf	d4,.setbit				; loop until all bits are set
		bra.s	.skip
; --------------------------------------------------------------

.ckupdate
	; checks if the frame had changed
		moveq	#0,d4
		move.w	(a1),a0					; load the parent to a0

		move.b	frame(a0),d4				; load display frame to d4
		cmp.b	dlast(a1),d4				; check if we are currently displaying this frame
		beq.s	.skip					; if so, just skip it

	if SAFE_DMA
		move.w	d2,-(sp)				; push d2 to stack because its modified
		bsr.w	AllocUpdate				; update art
		move.w	(sp)+,d2				; pop d2 from stack bto restore it
	else
		bsr.w	AllocUpdate				; update art
	endif
; --------------------------------------------------------------

.skip
		lea	dsize(a1),a1				; go to next object
		dbf	d0,.reloop				; loop for all objects
; --------------------------------------------------------------

	; finally, mark all the other bits free
		moveq	#0,d0
		move.w	d2,d0					; copy starting bit to d0
		lsr.w	#3,d0					; divide by 8 (8 bits per byte)

		add.w	#DynAllocTable,d0			; add alloc table to d0
		move.w	d0,a2					; load the final address to a2
; --------------------------------------------------------------

		dbset	dynallocbits,d1				; prepare max num of bits to d1
		sub.w	d2,d1					; sub the number of bits done from d1
		and.w	#7,d2					; get only the bit to d0
; --------------------------------------------------------------

.clrlp
		bclr	d2,(a2)					; clear the bit
		addq.b	#1,d2					; go to next bit

		bclr	#3,d2					; check if the byte is now all done
		sne	d0					; if yes, set d2
		ext.w	d0					; extend to word
		sub.w	d0,a2					; sub from the alloc pointer
		dbf	d1,.clrlp				; loop until all bits are cleared
		rts
; ==============================================================
; --------------------------------------------------------------
; Routine to initialize DMA queue
;
; thrash: d0-d2/a0
; --------------------------------------------------------------

dmaQueueInit:
		lea	DMAQueueBuf.w,a0			; load DMA queue address to a0
		move.w	a0,DMAQueueAddr.w			; reset DMA queue free entry pointer
		clr.w	(a0)					; set the first word as the end token

		dbset	dmaqueueentries,d0			; load amount of DMA queue entries to d0
		move.l	#$93979695,d1				; load all other registers to d1 (only every other byte is written)
; --------------------------------------------------------------

.initloop
		movep.l	d1,2(a0)				; fill every other byte with the rest of the registers (do not modify value!!)
		lea	2*7(a0),a0				; go to the next DMA entry
		dbf	d0,.initloop				; iterate through all DMA queue entries
		rts
; ==============================================================
; --------------------------------------------------------------
; Routine to process the DMA queue
;
; thrash: d0/a0
; --------------------------------------------------------------

dmaQueueProcess:
		lea	DMAQueueBuf.w,a0			; load DMA queue address to a0
		bra.s	.checkentry
; --------------------------------------------------------------

.nextentry
		move.w	d0,(a6)					; length to VDP
		move.l	(a0)+,(a6)				; length + source to VDP
		move.l	(a0)+,(a6)				; source to VDP
		move.l	(a0)+,(a6)				; initialize DMA!

.checkentry
		move.w	(a0)+,d0				; check if the next entry is used and load first value to d0
		bne.s	.nextentry				; if yes, branch
; --------------------------------------------------------------

		lea	DMAQueueBuf.w,a0			; load DMA queue address to a0
		move.w	a0,DMAQueueAddr.w			; reset DMA queue free entry pointer
		clr.w	(a0)					; set the first word as the end token
		rts
; --------------------------------------------------------------
