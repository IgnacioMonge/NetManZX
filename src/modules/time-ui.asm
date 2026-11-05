; ============================================
; Values share one column so the three rows line up under the title.
VAL_COL = 8

; ============================================
; showTime - Clock setup. RTC and SNTP share this screen; the zone
; selects the UTC offset used for SNTP and for the displayed clock.
; ============================================
showTime:
    xor a
    ld (Uart.log_enabled), a
    IFDEF HAS_ESXDOS
    call loadTime
    call restoreAfterFileIo
    ENDIF
    call rtcProbeSafe
.redrawFull
    ld hl, time_title
    call diagHeader
    call .frame
.redraw
    call Keyboard.waitBreakRelease
    call .refresh

.wait
    halt
    call .tick
    call Keyboard.checkBreak
    jp z, .exit
    ld b, 4
.wl
    halt
    call Keyboard.checkBreak
    jp z, .exit
    djnz .wl
    call Keyboard.inKeyNoWait
    and a
    jr z, .wait
    call Keyboard.keyClick
    cp 'y' : jp z, .sync
    cp 'Y' : jp z, .sync
    cp 'z' : jp z, .zone
    cp 'Z' : jp z, .zone
    jr .wait

.exit
    ld a, (Wifi.debug_log)
    ld (Uart.log_enabled), a
    jp renderListAndLoop

.paint
    gotoXY VAL_COL, 6
    call Rtc.kindName
    call Display.putStr

    gotoXY VAL_COL, 7
    ld a, (Rtc.valid)
    and a
    jr z, .paintSaved
    call timeCopyRtcToUi
    ld hl, rtc_ui_buf
    call printFields
    jr .paintZone
.paintSaved
    ld a, (Sntp.fields)
    and a
    jr z, .paintNone
    ld hl, Sntp.fields
    call printFields
    jr .paintZone
.paintNone
    ld hl, time_dashes
    call Display.putStr
.paintZone
    gotoXY VAL_COL, 8
    jp printZone

; Draw labels once; refresh only the values and the replaceable hint row.
.frame
    ld a, 6 : ld hl, time_rtc : call printAt0
    ld a, 7 : ld hl, time_clock : call printAt0
    ld a, 8 : ld hl, time_zone : call printAt0
    ld a, 10 : ld e, 3 : ld d, Display.ATTR_NORMAL
    jp Display.draw_hline

.refresh
    ld a, (#5C78)
    ld (time_last_frame), a
    call .clearDynamic
    call .paint
    ld a, 11 : ld hl, time_hint1 : jp printAt0

; Once-a-second refresh of the clock value on row 7, and of nothing else: the
; RTC name and the zone cannot change while this screen is up. The field is
; fixed width (DD/MM/YYYY HH:MM:SS), so it is overwritten in place with no
; clear step and no flicker. A source that cannot be re-read (esxDOS driver,
; or no chip at all) keeps the value probe captured.
; The key wait polls this every 5 frames, so an 8-bit frame compare is safe.
.tick
    ld a, (#5C78)
    ld hl, time_last_frame
    sub (hl)
    cp 50
    ret c
    ld a, (#5C78)
    ld (hl), a
    ld a, (Rtc.valid)
    push af
    call Rtc.read
    jr c, .tickFailed
    pop af
    jr .tickRtc
.tickFailed
    pop af
    and a
    ret z                   ; source was already invalid
    ld a, (Rtc.valid)
    and a
    ret nz                  ; esxDOS keeps the value captured by probe
    gotoXY VAL_COL, 7
    ld b, 19
    call .clearChars
    gotoXY VAL_COL, 7
    ld a, (Sntp.fields)
    and a
    jr z, .tickNone
    ld hl, Sntp.fields
    jp printFields
.tickNone
    ld hl, time_dashes
    jp Display.putStr
.tickRtc
    call timeCopyRtcToUi
    gotoXY VAL_COL, 7
    ld hl, rtc_ui_buf
    jp printFields

; Clear only fields that can change. Keeping the frame intact avoids a full
; diagnostic redraw after zone, set, sync, and status-message transitions.
.clearDynamic
    gotoXY VAL_COL, 6
    ld b, 14                ; widest source name: "not available"
    call .clearChars
    gotoXY VAL_COL, 7
    ld b, 19                ; "DD/MM/YYYY HH:MM:SS"
    call .clearChars
    gotoXY VAL_COL, 8
    ld b, 7                 ; "UTC+14"
    call .clearChars
    ld a, 11
    jp clearRowPixels

.clearChars
.clearCharsLoop
    ld a, ' '
    push bc
    call Display.putC
    pop bc
    djnz .clearCharsLoop
    ret

; Keep the clock live while a result waits for acknowledgement.
.showMsg
    push hl
    call .clearDynamic
    call .paint
    pop hl
    ld a, 11 : call printAt0
.msgWait
    call Keyboard.waitBreakRelease
    xor a
    ld (Keyboard.BASIC_KEY), a
    halt
    call .tick
    call Keyboard.inKeyNoWait
    and a
    jr z, .msgWait
    jp .redraw

; Zone editor. Its own modal screen in the standard dialog shape: title on
; rows 3-4, prompt on row 6, big-font field on rows 8-9 over the input colour
; band, help on row 11. Leaving it rebuilds the Time screen, so nothing is
; drawn on top of anything.
.zone
    ld hl, time_zonetitle
    call diagHeader
    ld a, 6 : ld hl, time_zoneprompt : call printAt0
    call setPassRows8
    ; Same help line as the other input dialogs; share their copy.
    ld a, 11 : ld hl, doStaticIP.sip_help : call printAt0
    ld hl, zone_buf
    ld b, 3
    ld a, 8 : ld (sti_line), a
    xor a
    ld (sti_len), a
    ld (hl), a
    ld a, 2
    ld (sti_mode), a
    call ipTextInput
    jp c, .redrawFull
    call parseZone
    jr c, .zoneBad
    call persistTime
    jr c, .zoneSaveFail
    jp .redrawFull
.zoneBad
    ld hl, time_badzone
    jr .zoneMsg
.zoneSaveFail
    ld hl, time_savefail
; Report on row 13, clear of both the field and the help row. No press-key
; banner: topClean only clears pixels up to row 14, so row 17 would survive
; the rebuild.
.zoneMsg
    ld a, 13 : call printAt0
    call waitAnyKey
    jp .redrawFull

.sync
    ld a, (Wifi.is_connected)
    and a
    jr nz, .syncGo
    ld hl, time_noconn
    jp .showMsg
.syncGo
    ; Let the AT exchange reach the UART log when the user enabled it.
    ld a, (Wifi.debug_log)
    ld (Uart.log_enabled), a
    ld a, 11 : call clearRowPixels
    ld a, 11 : ld hl, time_syncing : call printAt0
    call Sntp.sync
    push af
    call Uart.logFlushPending
    xor a
    ld (Uart.log_enabled), a
    pop af
    jp c, .syncFail
    ; Mirror the synchronized time into the RTC when writable
    call timeCopyUiToRtc
    call Rtc.writable
    jr c, .syncPersist
    call Rtc.writeTime
    jr c, .syncRtcFail
.syncPersist
    call persistTime
    jp c, .persistFail
    ld hl, time_syncok
    jp .showMsg
.syncRtcFail
    call persistTime
    jp c, .persistFail
    ld hl, time_rtcfail
    jp .showMsg
.syncFail
    ld hl, time_syncfail
    jp .showMsg

.persistFail
    ld hl, time_savefail
    jp .showMsg

; Convert the UI/SNTP order (year,month,date,hour,min,sec) to RTC order.
timeCopyUiToRtc:
    push bc
    push de
    push hl
    ld hl, Sntp.fields + 5
    ld de, Rtc.buf
    jr timeReverseSix

; Convert RTC order to the UI/SNTP order for display.
timeCopyRtcToUi:
    push bc
    push de
    push hl
    ld hl, Rtc.buf + 5
    ld de, rtc_ui_buf
; Preserve the old register/flag contract at a cost of six stack bytes.
timeReverseSix:
    ld b, 6
.loop
    ld a, (hl)
    ld (de), a
    dec hl
    inc de
    djnz .loop
    pop hl
    pop de
    pop bc
    ret

; Store the current time and zone (file only for esxDOS targets)
persistTime:
    IFDEF HAS_ESXDOS
    call saveTime
    call restoreAfterFileIo
    ENDIF
    ret

; Rtc.probe plus the rearm its UNO path needs: esxProbeDrvApi/esxProbeGetDate
; go through esxDOS rst $08, which scribbles the printer buffer holding
; Wifi.uart_busy, the log cursor and the indicator data.
; Output: CF from Rtc.probe (restoreAfterFileIo preserves AF).
rtcProbeSafe:
    call Rtc.probe
    IFDEF UNO
    call restoreAfterFileIo
    ENDIF
    ret

time_title      db "TIME AND DATE", 0
time_rtc        db "RTC:", 0
time_clock      db "Clock:", 0
time_zone       db "Zone:", 0
time_hint1      db "Y:Sync SNTP  Z:Zone  BREAK:Exit", 0
time_zonetitle  db "TIME ZONE", 0
time_zoneprompt db "Enter UTC offset (-12..+14):", 0
time_savefail   db "Time save failed.", 0
time_badzone    db "Invalid zone.", 0
time_noconn     db "No WiFi connection.", 0
time_syncing    db "Syncing with SNTP...", 0
time_syncok     db "SNTP sync OK.", 0
time_syncfail   db "SNTP sync failed.", 0
time_rtcfail    db "SNTP OK; RTC write failed.", 0
time_dashes     db "--", 0

    RTVAR rtc_ui_buf, 6
    RTVAR time_last_frame, 1
